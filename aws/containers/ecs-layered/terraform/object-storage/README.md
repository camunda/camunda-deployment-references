# Object storage layer

One backup bucket per cluster and one node ID lease bucket per zone. The lease relies on S3 conditional writes scoped to the bucket, so a lease bucket is never shared.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
