package camunda

// Topology
type Partition struct {
	PartitionId int    `json:"partitionId"`
	Role        string `json:"role"`
	Health      string `json:"health"`
}

type Broker struct {
	NodeId     int         `json:"nodeId"`
	Host       string      `json:"host"`
	Port       int         `json:"port"`
	Partitions []Partition `json:"partitions"`
	Version    string      `json:"version"`
}

type Cluster struct {
	Brokers           []Broker `json:"brokers"`
	ClusterSize       int      `json:"clusterSize"`
	PartitionsCount   int      `json:"partitionsCount"`
	ReplicationFactor int      `json:"replicationFactor"`
	GatewayVersion    string   `json:"gatewayVersion"`
}

// Deployment
type ProcessDefinition struct {
	ProcessDefinitionId      string `json:"processDefinitionId"`
	ProcessDefinitionVersion int    `json:"processDefinitionVersion"`
	ProcessDefinitionKey     int64  `json:"processDefinitionKey"`
	ResourceName             string `json:"resourceName"`
	TenantId                 string `json:"tenantId"`
}

type Deployment struct {
	ProcessDefinition ProcessDefinition `json:"processDefinition"`
}

type DeploymentInfo struct {
	DeploymentKey int64        `json:"deploymentKey"`
	Deployments   []Deployment `json:"deployments"`
	TenantId      string       `json:"tenantId"`
}
