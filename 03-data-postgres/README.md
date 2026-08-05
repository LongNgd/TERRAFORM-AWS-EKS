# 03-data-postgres

`03-data-postgres` là stack triển khai PostgreSQL HA trên EKS bằng Helm chart `bitnami/postgresql-ha`.

Stack này tách riêng data layer khỏi `02-platform` để tránh trộn cluster add-on với workload stateful.

## 1. Mục đích của stack

Stack này làm 2 phase:

- Phase 1: dựng PostgreSQL HA trên EKS bằng Helm
- Phase 2: bổ sung backup logical ra S3, metrics và ServiceMonitor tùy chọn

## 2. Phạm vi của stack

Stack này chịu trách nhiệm cho:
- namespace PostgreSQL
- PostgreSQL HA release bằng Helm
- Kubernetes secrets cho DB và Pgpool
- backup CronJob ra S3
- backup IAM role và IRSA annotation cho service account backup
- monitoring toggle cho metrics / ServiceMonitor

Stack này không tạo:
- VPC
- EKS cluster
- node group
- ALB ingress controller
- workload ứng dụng business

## 3. Input và output

### Input chính

| Biến | Bắt buộc | Ý nghĩa ngắn |
| --- | --- | --- |
| `infrastructure_state_bucket` | Có | Bucket chứa state của `01-infrastructure` |
| `infrastructure_state_key` | Không | Key chứa state của `01-infrastructure` |
| `postgres_namespace` | Không | Namespace đặt PostgreSQL |
| `postgres_release_name` | Không | Tên Helm release |
| `postgres_chart_version` | Không | Version chart `bitnami/postgresql-ha` |
| `postgresql_replica_count` | Không | Số PostgreSQL replicas; hiện repo cho phép giảm xuống để chạy trên cluster nhỏ |
| `postgresql_storage_class` | Không | StorageClass cho PVC |
| `postgresql_storage_size` | Không | Dung lượng PVC mỗi replica |
| `postgresql_username` | Không | User ứng dụng |
| `postgresql_password` | Có | Password của user ứng dụng |
| `postgresql_postgres_password` | Có | Password của superuser `postgres` |
| `postgresql_repmgr_password` | Có | Password cho `repmgr` |
| `pgpool_admin_password` | Có | Password admin của Pgpool |
| `pgpool_sr_check_password` | Có | Password sr-check của Pgpool |
| `enable_metrics` | Không | Bật postgres exporter metrics |
| `enable_service_monitor` | Không | Tạo ServiceMonitor nếu cluster có Prometheus Operator |
| `enable_s3_backup` | Không | Bật CronJob backup logical ra S3 |
| `create_backup_bucket` | Không | Tự tạo bucket backup riêng |
| `backup_s3_bucket_name` | Không | Bucket backup có sẵn nếu không tự tạo |
| `backup_schedule` | Không | Cron schedule của backup job |

### Output chính

| Output | Ý nghĩa ngắn |
| --- | --- |
| `postgres_namespace` | Namespace chứa PostgreSQL |
| `postgres_release_name` | Helm release name |
| `pgpool_service_name` | Service name để app kết nối DB |
| `pgpool_service_fqdn` | DNS nội bộ của Pgpool |
| `backup_bucket_name` | Bucket backup đang dùng nếu bật backup |
| `backup_cronjob_name` | CronJob backup nếu bật backup |

## 4. Luồng chạy tổng thể

1. Đọc remote state của `01-infrastructure`.
2. Kết nối vào EKS bằng provider `kubernetes` và `helm`.
3. Tạo namespace và secrets cho PostgreSQL/Pgpool.
4. Cài Helm chart `bitnami/postgresql-ha`.
5. Nếu bật phase 2, tạo S3 backup bucket tùy chọn, IAM role, IRSA annotation và CronJob backup.
6. Nếu bật metrics, chart sẽ bật exporter và có thể tạo ServiceMonitor.

Điều kiện quan trọng trước khi apply:
- cluster phải có `aws-ebs-csi-driver`
- `postgresql_storage_class` phải là StorageClass có thật trong cluster

## 5. Giải thích từng file

### `versions.tf`

```hcl
terraform {
  required_version = ">= 1.15.0, < 1.16.0"

  backend "s3" {}

  required_providers {
    aws        = ...
    helm       = ...
    kubernetes = ...
  }
}
```

Ý nghĩa:
- khóa version Terraform CLI
- dùng remote backend S3 riêng cho stack `03-data-postgres`
- pin provider AWS, Helm và Kubernetes

### `providers.tf`

File này làm 3 việc:
- cấu hình AWS provider theo `aws_region`
- đọc remote state của `01-infrastructure`
- cấu hình provider `kubernetes` và `helm` để kết nối vào EKS cluster đã có

Điểm quan trọng:
- stack này không tự tạo lại cluster
- nó lấy `cluster_name` từ state của `01`
- sau đó gọi `data.aws_eks_cluster.main` để lấy endpoint và certificate authority
- auth vào cluster bằng `aws eks get-token`
- nó cũng đọc OIDC provider ARN từ remote state của `01` để cấu hình IRSA cho backup job

### `variables.tf`

File này chứa toàn bộ biến cấu hình cho 2 phase.

Nhóm biến chính:
- biến kết nối hạ tầng: `infrastructure_state_bucket`, `infrastructure_state_key`
- biến Helm/PostgreSQL: `postgres_release_name`, `postgres_chart_version`, `postgresql_*`, `pgpool_*`
- biến monitoring: `enable_metrics`, `enable_service_monitor`
- biến backup: `enable_s3_backup`, `create_backup_bucket`, `backup_*`

### `locals.tf`

File này tạo các giá trị dùng lại nhiều lần:
- tên secret cho PostgreSQL
- tên secret cho Pgpool
- tên service account backup
- tên bucket backup cuối cùng
- FQDN nội bộ của Pgpool service
- hostname nội bộ của PostgreSQL primary cho backup full dump

Ví dụ:
- `local.pgpool_service_name`
- `local.pgpool_service_fqdn`

Giá trị này rất quan trọng vì app trong cluster sẽ kết nối qua Pgpool chứ không gọi thẳng từng pod PostgreSQL.

### `main.tf`

Đây là file triển khai phase 1.

Nó tạo:
- namespace `data` hoặc namespace bạn cấu hình
- secret cho PostgreSQL passwords
- secret cho Pgpool passwords
- Helm release `bitnami/postgresql-ha`

Ý nghĩa các resource chính:

#### `kubernetes_namespace_v1.postgres`
- tạo namespace riêng cho data layer

#### `kubernetes_secret_v1.postgresql_auth`
- chứa:
  - password của app user
  - password của `postgres`
  - password của `repmgr`

Chart `postgresql-ha` sẽ đọc secret này qua `postgresql.existingSecret`.

#### `kubernetes_secret_v1.pgpool_auth`
- chứa:
  - password admin của Pgpool
  - password sr-check của Pgpool

Chart sẽ đọc secret này qua `pgpool.existingSecret`.

#### `helm_release.postgresql_ha`
- cài chart `bitnami/postgresql-ha`
- dùng `templatefile()` để render values từ file `helm-values/postgresql-ha-values.yaml.tftpl`

Điểm quan trọng:
- release này là trái tim của phase 1
- chính Helm chart sẽ sinh ra các resource Kubernetes tương ứng như PostgreSQL StatefulSet, Pgpool Deployment, Service và PVC bên trong cluster
- Terraform không tự viết tay các manifest DB, mà để Helm chart quản lý

### `backup.tf`

Đây là file triển khai phase 2.

Nó xử lý 3 nhóm việc:

#### 1. Hạ tầng S3 backup
- tùy chọn tạo bucket backup riêng
- bật ownership controls
- bật public access block
- bật versioning
- bật encryption
- thêm lifecycle retention

#### 2. IAM và IRSA cho backup job
- tạo IAM role cho backup job
- gắn policy ghi S3
- tạo service account backup trong Kubernetes
- annotate service account với `eks.amazonaws.com/role-arn` để backup pod dùng IRSA lấy quyền ghi S3

#### 3. Kubernetes CronJob backup
- tạo `kubernetes_cron_job_v1.backup`
- container thứ nhất chạy `pg_dumpall`
- ghi file dump nén vào `emptyDir`
- container thứ hai dùng AWS CLI upload file đó lên S3

Lưu ý thiết kế hiện tại:
- backup đang dùng `emptyDir` làm volume tạm, không có PVC backup riêng
- mục tiêu là dump xong rồi đẩy thẳng lên S3
- `pg_dumpall` đi thẳng vào PostgreSQL primary, không đi qua `pgpool`, để tránh lỗi SCRAM và đảm bảo full cluster logical dump

### `outputs.tf`

File này xuất ra các giá trị quan trọng để vận hành:
- namespace của PostgreSQL
- tên Helm release
- tên service Pgpool
- FQDN nội bộ của Pgpool
- bucket backup đang dùng
- tên CronJob backup

### `helm-values/postgresql-ha-values.yaml.tftpl`

Đây là file template values của chart `bitnami/postgresql-ha`.

File này render các cấu hình quan trọng như:
- `postgresql.replicaCount`
- `postgresql.existingSecret`
- `persistence.storageClass`
- `persistence.size`
- `postgresql.resources`
- `pgpool.replicaCount`
- `pgpool.existingSecret`
- `postgresql.image`
- `pgpool.image`
- `metrics.image`
- `service.type`
- `metrics.enabled`
- `metrics.serviceMonitor.enabled`

Nói ngắn gọn:
- `main.tf` cài Helm chart
- file `.tftpl` quyết định chart đó được cấu hình như thế nào

## 6. Phase 1: PostgreSQL HA bằng Helm

Helm chart dùng:
- repository: `https://charts.bitnami.com/bitnami`
- chart: `postgresql-ha`

Các mặc định hiện tại của repo đang nghiêng về cấu hình gọn hơn để chạy được trên cluster nhỏ:
- `postgresql.replicaCount = 2`
- `postgresql.podAntiAffinityPreset = soft`
- `pgpool.replicaCount = 1`
- `pgpool.podAntiAffinityPreset = soft`
- `persistence.enabled = true`
- `service.type = ClusterIP`
- `enable_metrics = false` trong `terraform.tfvars` hiện tại

Lưu ý thực tế:
- nếu muốn tăng lại mức HA, bạn phải đảm bảo cluster đủ CPU, memory, pod slots và khả năng schedule giữa các node/AZ
- nếu backend chạy trên máy local, không dùng trực tiếp DNS `*.svc.cluster.local`; hãy dùng `kubectl port-forward`

App trong cluster nên kết nối qua:

```text
<release-name>-pgpool.<namespace>.svc.cluster.local:5432
```

Ví dụ với mặc định hiện tại:

```text
postgresql-ha-pgpool.data.svc.cluster.local:5432
```

## 7. Phase 2: Backup và monitoring

### Backup ra S3

Khi `enable_s3_backup = true`, stack sẽ tạo:
- service account riêng cho backup
- IAM role với quyền ghi S3
- IRSA annotation trên service account backup
- CronJob chạy `pg_dumpall | gzip` rồi upload lên S3

Lưu ý:
- đây là logical backup, không phải PITR
- backup image và upload image đang để public image mặc định; production lâu dài nên thay bằng image nội bộ của team

### Monitoring

Khi `enable_metrics = true`, chart sẽ bật exporter metrics.

Khi thêm `enable_service_monitor = true`, chart sẽ tạo `ServiceMonitor`.

Lưu ý:
- cluster phải có Prometheus Operator CRDs, nếu không Helm release sẽ fail

## 8. Luồng apply thực tế

### Bước 1. Chuẩn bị backend

Tạo `backend.hcl` từ file mẫu:

```hcl
bucket       = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
key          = "longnd/dev/data-postgres.tfstate"
region       = "ap-southeast-1"
encrypt      = true
use_lockfile = true
```

### Bước 2. Chuẩn bị `terraform.tfvars`

Từ `terraform.tfvars.example`, điền các password thật bằng `TF_VAR_*` hoặc secret manager.

### Bước 3. Chạy Terraform

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -out data-postgres.tfplan
terraform apply data-postgres.tfplan
```

## 9. Kiểm tra sau khi apply

### Kubernetes

```bash
kubectl get pods -n data -o wide
kubectl get pvc -n data
kubectl get svc -n data
kubectl get cronjob -n data
```

Bạn muốn thấy:
- PostgreSQL và Pgpool pods `Running`
- PVC `Bound`
- CronJob backup đã tồn tại

### AWS

- kiểm tra IAM role và IRSA annotation của service account backup nếu bật
- kiểm tra bucket backup nếu `create_backup_bucket = true`
- kiểm tra EBS volumes được tạo nếu PVC đã `Bound`

## 10. Restore test khuyến nghị

Stack này chưa tự động tạo restore job vì restore test production nên làm có chủ đích.

Khuyến nghị tối thiểu:
1. Tạo namespace test riêng, ví dụ `restore-test`.
2. Deploy một PostgreSQL tạm thời hoặc một DB rỗng để test.
3. Tải một file backup mới nhất từ S3.
4. Chạy `gunzip -c backup.sql.gz | psql ...` để import vào DB test.
5. Kiểm tra bảng, schema và quyền truy cập sau restore.

Bạn cũng có thể test kết nối nhanh từ local qua `port-forward`:

```bash
kubectl -n data port-forward svc/postgresql-ha-pgpool 15432:5432
```

Khi đó app local hoặc DBeaver dùng:
- host: `127.0.0.1`
- port: `15432`

DNS nội bộ như `postgresql-ha-pgpool.data.svc.cluster.local` chỉ dùng được với pod chạy bên trong cluster.

## 11. Troubleshooting

### Helm release fail với `ServiceMonitor`

Nguyên nhân thường gặp:
- cluster chưa có Prometheus Operator CRDs

Cách xử lý:
- tắt `enable_service_monitor`
- hoặc cài Prometheus Operator trước

### Backup CronJob fail khi upload S3

Nguyên nhân thường gặp:
- bucket name chưa đúng
- IRSA chưa vào đúng service account backup hoặc OIDC/IAM chưa sẵn sàng
- IAM role backup thiếu quyền S3

Cách xử lý:
- kiểm tra `backup_bucket_name`
- kiểm tra service account backup có annotation `eks.amazonaws.com/role-arn`
- kiểm tra IAM role trust `sts:AssumeRoleWithWebIdentity`
- kiểm tra logs của job backup

### Pod PostgreSQL không lên do PVC

Nguyên nhân thường gặp:
- storage class không tồn tại
- thiếu disk quota
- cluster chưa cài `aws-ebs-csi-driver`

Cách xử lý:
- kiểm tra `postgresql_storage_class`
- kiểm tra `kubectl describe pvc -n <namespace>`
- kiểm tra `kubectl get csidriver`
- kiểm tra `kubectl get pods -n kube-system | findstr ebs`

### Pod PostgreSQL hoặc Pgpool bị `ImagePullBackOff`

Nguyên nhân thường gặp:
- chart đang dùng Debian-based tags cũ của Bitnami
- image cần pull từ `bitnamilegacy/*` thay vì `bitnami/*`

Cách xử lý:
- kiểm tra `kubectl describe pod -n data <pod-name>`
- kiểm tra file values template đang override `postgresql.image`, `pgpool.image`, `metrics.image` đúng repo/tag

## 12. Production checklist

- chọn `postgresql_replica_count` theo năng lực thật của cluster; nếu tăng replica thì phải tăng capacity tương ứng
- dùng explicit resources, không dựa vào `resourcesPreset`
- backup S3 phải bật và được kiểm tra định kỳ
- restore test phải được chạy định kỳ ngoài production path
- ServiceMonitor chỉ bật khi cluster có Prometheus Operator
- cân nhắc dùng image nội bộ thay cho image public của backup job
- xác nhận EBS CSI driver đã chạy và StorageClass dùng trong tfvars tồn tại thật trong cluster
- cân nhắc node group riêng cho database nếu workload lớn

## 13. Tóm tắt dễ nhớ

`03-data-postgres` là stack data layer cho PostgreSQL HA trên EKS.

Nó làm 2 phase chính:
1. dựng PostgreSQL HA bằng Helm chart `bitnami/postgresql-ha`
2. bổ sung backup logical ra S3 và monitoring toggle cho production cơ bản
