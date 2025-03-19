package utils

import (
	"context"
	"encoding/base64"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/service/eks/types"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"os/exec"
	"sigs.k8s.io/aws-iam-authenticator/pkg/token"
	"sync/atomic"
	"testing"
	"time"

	batchv1 "k8s.io/api/batch/v1"
)

func WaitForJobCompletion(clientset *kubernetes.Clientset, namespace, jobName string, timeout time.Duration, listOptions metav1.ListOptions) error {
	// Create a context
	ctx := context.Background()

	// Watch for job events
	watch, err := clientset.BatchV1().Jobs(namespace).Watch(ctx, listOptions)
	if err != nil {
		return fmt.Errorf("Error creating watcher: %v", err)
	}
	defer watch.Stop()

	// Channel to receive events
	eventChan := watch.ResultChan()

	// Loop to wait for job completion
	for {
		select {
		case event := <-eventChan:
			job, ok := event.Object.(*batchv1.Job)
			if !ok {
				return fmt.Errorf("Unexpected event received: %v", event)
			}
			if job.Name == jobName {
				// Check if the job has completed
				if job.Status.CompletionTime != nil {
					// The job has completed, check if it succeeded
					// The job has completed, check if it succeeded
					if job.Status.Succeeded == 1 {
						return nil // Job completed successfully
					} else {
						return fmt.Errorf("Job completed with errors")
					}
				}
			}
		case <-time.After(timeout):
			return fmt.Errorf("Timeout: job did not complete after %v minutes", timeout)
		}
	}
}

func CreateIfNotExistsNamespace(t *testing.T, kubeCtlOptions *k8s.KubectlOptions, namespace string) {
	_, errFindNamespace := k8s.GetNamespaceE(t, kubeCtlOptions, namespace)
	if errFindNamespace != nil {
		if errors.IsNotFound(errFindNamespace) {
			k8s.CreateNamespace(t, kubeCtlOptions, namespace)
		} else {
			require.NoError(t, errFindNamespace)
		}
	}
}

func CreateIfNotExistsServiceAccount(t *testing.T, kubeCtlOptions *k8s.KubectlOptions, serviceAccountName string, annotations map[string]string) {
	_, errFindSA := k8s.GetServiceAccountE(t, kubeCtlOptions, serviceAccountName)
	if errFindSA != nil {
		if errors.IsNotFound(errFindSA) {
			// Create service account with annotations if it does not exist
			serviceAccount := &corev1.ServiceAccount{
				ObjectMeta: metav1.ObjectMeta{
					Name:        serviceAccountName,
					Namespace:   kubeCtlOptions.Namespace,
					Annotations: annotations,
				},
			}
			clientset, errClient := k8s.GetKubernetesClientFromOptionsE(t, kubeCtlOptions)
			require.NoError(t, errClient)
			_, errSA := clientset.CoreV1().ServiceAccounts(kubeCtlOptions.Namespace).Create(context.Background(), serviceAccount, metav1.CreateOptions{})
			require.NoError(t, errSA)
		} else {
			require.NoError(t, errFindSA)
		}
	}
}

func GenerateKubeConfigFromAWS(t *testing.T, region, clusterName, awsProfile, configOutputPath string) {
	cmd := exec.Command("aws", "eks", "--region", region, "update-kubeconfig", "--name", clusterName, "--profile", awsProfile, "--kubeconfig", configOutputPath)
	_, errCmdKubeProfile := cmd.Output()
	require.NoError(t, errCmdKubeProfile)
}

// WaitUntilKubeClusterIsReady waits until the kube cluster is read or returns an error
func WaitUntilKubeClusterIsReady(cluster *types.Cluster, timeout time.Duration, expectedNodesCount uint64) error {
	// https://github.com/kubernetes/client-go
	// https://www.rushtehrani.com/post/using-kubernetes-api
	// https://rancher.com/using-kubernetes-api-go-kubecon-2017-session-recap
	// https://gianarb.it/blog/kubernetes-shared-informer
	// https://stackoverflow.com/questions/60547409/unable-to-obtain-kubeconfig-of-an-aws-eks-cluster-in-go-code/60573982#60573982

	fmt.Printf("Expecting %d nodes to join cluster %s\n", expectedNodesCount, *cluster.Name)

	clientSet, err := NewKubeClientSet(cluster)
	if err != nil {
		return err
	}

	factory := informers.NewSharedInformerFactory(clientSet, 0)
	informer := factory.Core().V1().Nodes().Informer()
	stopChannel := make(chan struct{})
	var countOfWorkerNodes uint64 = 0

	_, errEventHandler := informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj interface{}) {
			node := obj.(*corev1.Node)
			fmt.Printf("Worker Node %s has joined the EKS cluster at %s\n", node.Name, node.CreationTimestamp)
			atomic.AddUint64(&countOfWorkerNodes, 1)

			// this will not prevent race condition, a lock on the
			// operation would be necessary, in case of too many nodes
			// joining the cluster, this function will panic
			if countOfWorkerNodes == expectedNodesCount {
				stopChannel <- struct{}{}
			} else if countOfWorkerNodes > expectedNodesCount {
				fmt.Printf("Warning: More nodes (%d) than expected (%d) have joined the cluster.\n", countOfWorkerNodes, expectedNodesCount)
			}
		},
	})
	if errEventHandler != nil {
		return errEventHandler
	}

	go informer.Run(stopChannel)
	go func() {
		// wait to receive a signal to close the channel
		<-stopChannel
		close(stopChannel)
	}()

	select {
	case <-stopChannel:
		msg := "All worker nodes have joined the Kube cluster"
		fmt.Println(msg)
	case <-time.After(timeout):
		msg := "Not all worker nodes have joined the Kube cluster"
		fmt.Println(msg)
		return errors.NewResourceExpired(msg)
	}
	return nil
}

// NewKubeClientSet generate a kubernetes.Clientset from an EKS Cluster
func NewKubeClientSet(cluster *types.Cluster) (*kubernetes.Clientset, error) {
	gen, err := token.NewGenerator(true, false)
	if err != nil {
		return nil, err
	}
	opts := &token.GetTokenOptions{
		ClusterID: *cluster.Name,
	}
	tok, err := gen.GetWithOptions(opts)
	if err != nil {
		return nil, err
	}
	ca, err := base64.StdEncoding.DecodeString(*cluster.CertificateAuthority.Data)
	if err != nil {
		return nil, err
	}
	clientSet, err := kubernetes.NewForConfig(
		&rest.Config{
			Host:        *cluster.Endpoint,
			BearerToken: tok.Token,
			TLSClientConfig: rest.TLSClientConfig{
				CAData: ca,
			},
		},
	)
	if err != nil {
		return nil, err
	}
	return clientSet, nil
}
