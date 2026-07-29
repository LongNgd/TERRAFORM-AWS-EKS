# 02-platform

`02-platform` là stack cài phần platform layer lên EKS đã được tạo ở `01-infrastructure`.
Stack này không tạo lại VPC, EKS hay RDS. Nó đọc remote state của `01-infrastructure`, kết nối vào cluster hiện có, rồi cài add-on và workload mẫu.

Trong repo này, `02-platform` đang làm 2 việc chính:
- cài `aws-load-balancer-controller` bằng Helm
- tùy chọn deploy sample app để kiểm tra ALB ingress hoạt động

## 1. Mục đích của `02-platform`

Mục tiêu của stack này là tách phần Kubernetes/Helm ra khỏi phần hạ tầng nền.

Lợi ích của cách tách này:
- tránh bootstrap problem khi EKS chưa sẵn sàng mà provider Kubernetes đã cố kết nối
- cho phép apply hạ tầng AWS trước, sau đó mới apply platform add-on
- dễ tách trách nhiệm giữa team infra và team platform

Nói ngắn gọn:
- `01-infrastructure` tạo cluster
- `02-platform` vào cluster đó để cài thứ chạy bên trong cluster

## 2. Phạm vi của stack

Stack này chịu trách nhiệm cho lớp platform bên trong cluster:
- cấu hình provider Kubernetes và Helm
- cài add-on bắt buộc cho ingress ALB
- tùy chọn tạo workload mẫu để verify end-to-end

Stack này không tạo lại:
- VPC
- subnet
- EKS cluster
- node group
- RDS
- app bucket nền tảng

## 3. Input và output

### Input chính

| Biến | Bắt buộc | Ý nghĩa ngắn |
| --- | --- | --- |
| `aws_region` | Không | Region chứa EKS cluster và remote state |
| `infrastructure_state_bucket` | Có | Bucket chứa state của `01-infrastructure` |
| `infrastructure_state_key` | Không | Key của state file `01-infrastructure` |
| `load_balancer_controller_chart_version` | Không | Version chart Helm của AWS Load Balancer Controller |
| `load_balancer_controller_replica_count` | Không | Số replica của controller |
| `deploy_sample_app` | Không | Có deploy workload mẫu để test hay không |
| `certificate_arn` | Không | ACM certificate ARN để bật HTTPS cho sample ingress |

### Data phụ thuộc từ `01-infrastructure`

Stack này đọc remote state của `01-infrastructure` để lấy:
- `cluster_name`
- `vpc_id`
- `public_subnet_ids`

Các giá trị đó được dùng để:
- kết nối provider `kubernetes`
- kết nối provider `helm`
- render Helm values cho load balancer controller
- cấu hình sample ingress

### Output chính

| Output | Ý nghĩa ngắn |
| --- | --- |
| `sample_alb_hostname` | Hostname của ALB tạo từ sample ingress nếu sample app được deploy |

Output này chỉ có ý nghĩa khi `deploy_sample_app = true`.

## 4. Luồng chạy tổng thể

Luồng logic:

1. Terraform dùng remote backend riêng cho stack platform.
2. Terraform đọc remote state của `01-infrastructure` từ S3.
3. Terraform lấy `cluster_name` từ state đó.
4. Terraform gọi `data.aws_eks_cluster.main` để lấy endpoint và CA của cluster.
5. Provider `kubernetes` và `helm` dùng AWS CLI `eks get-token` để authenticate vào cluster.
6. Terraform render file values cho Helm chart `aws-load-balancer-controller`.
7. Terraform cài chart bằng `helm_release`.
8. Nếu `deploy_sample_app = true`, Terraform tạo namespace, service account, deployment, service và ingress trong Kubernetes.
9. Ingress này được AWS Load Balancer Controller quan sát và tạo ALB ngoài AWS.
10. Terraform output hostname của ALB nếu đã xuất hiện.

## 5. Giải thích từng file

### `versions.tf`

```hcl
terraform {
  required_version = ">= 1.15.0, < 1.16.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.56.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
  }
}
```

Ý nghĩa:
- backend state riêng cho platform stack
- pin provider AWS, Helm và Kubernetes
- đảm bảo môi trường apply nhất quán hơn

### `providers.tf`

Đây là file quan trọng nhất của stack này.

#### AWS provider

```hcl
provider "aws" {
  region = var.aws_region
}
```

Ý nghĩa:
- dùng AWS provider để đọc EKS cluster và remote state liên quan

#### Đọc remote state của `01-infrastructure`

```hcl
data "terraform_remote_state" "infrastructure" {
  backend = "s3"

  config = {
    bucket       = var.infrastructure_state_bucket
    key          = var.infrastructure_state_key
    region       = var.aws_region
    use_lockfile = true
  }
}
```

Ý nghĩa:
- stack này không tự đoán cluster ở đâu
- nó đọc chính xác output đã được stack `01-infrastructure` ghi vào state

Các biến quan trọng:
- `infrastructure_state_bucket`
  - bucket chứa state của `01`
- `infrastructure_state_key`
  - key của file state `01`

#### Đọc EKS cluster để lấy endpoint và CA

```hcl
data "aws_eks_cluster" "main" {
  name = data.terraform_remote_state.infrastructure.outputs.cluster_name
}
```

Ý nghĩa:
- sau khi biết `cluster_name`, Terraform gọi AWS API để lấy chi tiết cluster
- cần các thông tin này cho provider `kubernetes` và `helm`

#### Kubernetes provider

```hcl
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--region",
      var.aws_region,
      "--cluster-name",
      data.aws_eks_cluster.main.name
    ]
  }
}
```

Ý nghĩa:
- `host` là API endpoint của EKS
- `cluster_ca_certificate` là CA certificate để trust API server
- khối `exec` gọi `aws eks get-token` để lấy token truy cập cluster

Nói đơn giản:
- Terraform không cần kubeconfig file thủ công
- nó tự hỏi AWS để lấy token truy cập vào EKS

#### Helm provider

Provider `helm` cũng dùng cùng endpoint, CA và `aws eks get-token` như provider `kubernetes`.

Ý nghĩa:
- Helm chart được cài trực tiếp vào cluster EKS đó

### `variables.tf`

Các biến đáng chú ý:

- `infrastructure_state_bucket`
  - bắt buộc phải điền đúng bucket chứa state của `01`

- `infrastructure_state_key`
  - mặc định là `longnd/dev/infrastructure.tfstate`

- `load_balancer_controller_chart_version`
  - version chart Helm cần cài

- `load_balancer_controller_replica_count`
  - số replica controller, mặc định là `2`

- `deploy_sample_app`
  - nếu `true`, stack sẽ deploy workload mẫu

- `certificate_arn`
  - nếu điền ACM certificate ARN, sample ingress sẽ bật HTTPS

## 6. Giải thích `load-balancer-controller.tf`

```hcl
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.load_balancer_controller_chart_version
  ...
}
```

Đây là resource cài AWS Load Balancer Controller bằng Helm.

### 5.1. Controller này dùng để làm gì

AWS Load Balancer Controller là thành phần trong Kubernetes có nhiệm vụ:
- quan sát `Ingress` và một số resource Kubernetes khác
- gọi AWS API để tạo ALB/NLB tương ứng
- quản lý listener, target group, rule và đăng ký targets

Trong repo này, nó là cầu nối giữa:
- resource Kubernetes `Ingress`
- và ALB thật ở phía AWS

### 5.2. Các tùy chọn quan trọng trong `helm_release`

- `atomic = true`
  - nếu cài thất bại, Helm rollback tự động

- `cleanup_on_fail = true`
  - dọn các tài nguyên tạm nếu install fail

- `timeout = 900`
  - cho phép chart có thời gian dài hơn để cài xong

- `wait = true`
  - Terraform chờ Helm release sẵn sàng

### 5.3. Render Helm values bằng `templatefile`

```hcl
values = [
  templatefile(
    "${path.module}/helm-values/aws-load-balancer-controller-values.yaml.tftpl",
    {
      cluster_name  = data.terraform_remote_state.infrastructure.outputs.cluster_name
      aws_region    = var.aws_region
      vpc_id        = data.terraform_remote_state.infrastructure.outputs.vpc_id
      replica_count = var.load_balancer_controller_replica_count
    }
  )
]
```

Ý nghĩa:
- Terraform render file template values trước
- rồi truyền nội dung đó vào Helm chart

Điểm hay của cách này:
- values phụ thuộc trực tiếp vào output thực tế của stack `01`
- không cần hardcode `cluster_name` hay `vpc_id`

## 7. Giải thích file Helm values template

File: `helm-values/aws-load-balancer-controller-values.yaml.tftpl`

```yaml
clusterName: ${cluster_name}
region: ${aws_region}
vpcId: ${vpc_id}
replicaCount: ${replica_count}

serviceAccount:
  create: true
  name: aws-load-balancer-controller
```

Ý nghĩa từng dòng:
- `clusterName`
  - controller cần biết nó đang phục vụ cluster nào
- `region`
  - region AWS tương ứng
- `vpcId`
  - để controller thao tác đúng VPC
- `replicaCount`
  - số replica của controller
- `serviceAccount.name`
  - phải trùng với Pod Identity association được tạo ở `01-infrastructure`

Điểm quan trọng:
- service account tên `aws-load-balancer-controller` phải khớp với association trong `01-infrastructure/eks.tf`
- nếu lệch tên, pod sẽ không assume đúng IAM role

## 8. Giải thích `sample-app.tf`

File này chỉ có tác dụng khi `deploy_sample_app = true`.

Mục tiêu của nó là tạo một workload mẫu để xác minh:
- Kubernetes provider hoạt động
- AWS Load Balancer Controller hoạt động
- ALB được tạo thành công
- traffic từ Internet đi vào pod được

### 7.1. Local annotations cho ingress

`local.sample_ingress_annotations` tạo ra map annotations cho ALB ingress.

Các annotation chính:
- `alb.ingress.kubernetes.io/scheme = "internet-facing"`
  - tạo ALB public
- `alb.ingress.kubernetes.io/target-type = "ip"`
  - target là pod IP
- `alb.ingress.kubernetes.io/healthcheck-path = "/"`
  - path health check của pod backend
- `alb.ingress.kubernetes.io/subnets`
  - chỉ rõ ALB dùng các public subnet từ output của `01`

Nếu `certificate_arn` rỗng:
- ingress chỉ mở HTTP 80

Nếu `certificate_arn` có giá trị:
- ingress mở cả HTTP 80 và HTTPS 443
- đồng thời redirect HTTP sang HTTPS

### 7.2. Namespace `app`

```hcl
resource "kubernetes_namespace_v1" "app" {
  count = var.deploy_sample_app ? 1 : 0
}
```

Ý nghĩa:
- tạo namespace riêng cho sample app

### 7.3. Service account `app-sa`

```hcl
resource "kubernetes_service_account_v1" "app" {
  count = var.deploy_sample_app ? 1 : 0
}
```

Ý nghĩa:
- service account này có tên `app-sa`
- tên này khớp với Pod Identity association đã được tạo ở `01-infrastructure`

### 7.4. Deployment mẫu

```hcl
resource "kubernetes_deployment_v1" "sample" {
  count = var.deploy_sample_app ? 1 : 0
}
```

Deployment này chạy image:
- `registry.k8s.io/echoserver:1.10`

Đặc điểm:
- 2 replicas
- expose port 8080
- có readiness probe
- có requests/limits tài nguyên

Ý nghĩa:
- đủ nhỏ để test nhanh
- đủ chuẩn để ingress/ALB trỏ vào được

### 7.5. Service

```hcl
resource "kubernetes_service_v1" "sample" {
  count = var.deploy_sample_app ? 1 : 0
}
```

Ý nghĩa:
- tạo `ClusterIP` service tên `sample-echo`
- service map port 80 sang container port 8080

### 7.6. Ingress

```hcl
resource "kubernetes_ingress_v1" "sample" {
  count = var.deploy_sample_app ? 1 : 0
  ...
  depends_on = [helm_release.aws_load_balancer_controller]
}
```

Ý nghĩa:
- tạo ingress class `alb`
- route path `/test` vào service `sample-echo`
- `depends_on` đảm bảo controller đã được cài trước khi ingress xuất hiện

Sau khi ingress này được tạo:
- AWS Load Balancer Controller sẽ gọi AWS API
- tạo ALB, target group, listener và rule ở bên AWS

## 9. Giải thích `outputs.tf`

```hcl
output "sample_alb_hostname" {
  value = var.deploy_sample_app ? try(
    kubernetes_ingress_v1.sample[0].status[0].load_balancer[0].ingress[0].hostname,
    null
  ) : null
}
```

Ý nghĩa:
- nếu sample app được deploy, Terraform cố lấy hostname của ALB từ status của ingress
- nếu ALB chưa sẵn sàng ngay, output có thể tạm thời là `null`

Đây là output tiện để verify nhanh sau khi apply.

## 10. Luồng apply thực tế

### Bước 1. Chuẩn bị backend

Tạo `backend.hcl` từ file mẫu:

```hcl
bucket       = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
key          = "longnd/dev/platform.tfstate"
region       = "ap-southeast-1"
encrypt      = true
use_lockfile = true
```

### Bước 2. Chuẩn bị `terraform.tfvars`

Ví dụ:

```hcl
aws_region                  = "ap-southeast-1"
infrastructure_state_bucket = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
infrastructure_state_key    = "longnd/dev/infrastructure.tfstate"
deploy_sample_app           = true

# certificate_arn = "arn:aws:acm:ap-southeast-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

load_balancer_controller_replica_count = 2
```

### Bước 3. Chạy Terraform

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -out platform.tfplan
terraform apply platform.tfplan
```

### Bước 4. Verify

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n app -o wide
kubectl get ingress -n app
terraform output sample_alb_hostname
```

Sau khi ALB hostname xuất hiện, test sample app qua path:

```text
http://<sample_alb_hostname>/test
```

Hoặc nếu đã cấu hình `certificate_arn`:

```text
https://<sample_alb_hostname>/test
```

## 11. Phụ thuộc với stack khác

Phụ thuộc vào `00-bootstrap`:
- cần backend S3 tồn tại

Phụ thuộc vào `01-infrastructure`:
- cần remote state của `01` có sẵn
- cần EKS cluster đã tạo xong
- cần node group hoạt động để pods có chỗ chạy
- cần Pod Identity association và IAM role đã sẵn sàng

## 12. Điểm tốt của stack này

- tách riêng Kubernetes/Helm layer khỏi infra layer
- đọc trực tiếp remote state thay vì hardcode thông tin cluster
- cài `aws-load-balancer-controller` bằng Helm có `atomic`, `wait`, `cleanup_on_fail`
- render values từ output thực tế của stack `01`
- sample app giúp verify end-to-end nhanh

## 13. Production checklist

Trước khi dùng stack này cho production, nên kiểm tra các mục sau:

- `infrastructure_state_bucket` và `infrastructure_state_key` đang trỏ đúng state của môi trường tương ứng
- `load_balancer_controller_chart_version` đã được review tương thích với EKS version hiện tại
- `load_balancer_controller_replica_count >= 2` cho môi trường HA
- service account trong Helm values vẫn khớp với Pod Identity association của `01-infrastructure`
- `deploy_sample_app = false` trước khi go-live
- nếu còn cần ingress public thì đã cấu hình `certificate_arn` để bật HTTPS và redirect từ HTTP sang HTTPS
- cân nhắc nâng `client.authentication.k8s.io/v1beta1` lên `v1` cho provider `kubernetes` và `helm`
- xác nhận IAM role của load balancer controller đủ quyền nhưng không rộng quá mức cần thiết
- verify controller đã chạy ổn định trước khi deploy workload thật

## 14. Điểm cần lưu ý trước production

- `deploy_sample_app` mặc định đang `true`, không nên giữ khi go-live
- nếu không set `certificate_arn`, sample ingress chỉ mở HTTP
- provider `kubernetes` và `helm` đang dùng `client.authentication.k8s.io/v1beta1`, nên nâng sang `v1`
- chart version hiện được pin, tốt cho tính ổn định nhưng cần quy trình review khi nâng version

## 15. Troubleshooting

### Lỗi provider `kubernetes` hoặc `helm` không kết nối được cluster

Nguyên nhân thường gặp:
- state của `01-infrastructure` chưa đúng hoặc chưa tồn tại
- AWS CLI chưa đăng nhập đúng account hoặc region
- EKS endpoint không reachable từ nơi chạy Terraform

Cách xử lý:
- kiểm tra `infrastructure_state_bucket` và `infrastructure_state_key`
- kiểm tra `aws sts get-caller-identity` và region đang dùng
- nếu cluster private-only, chạy Terraform từ trong VPC hoặc runner có network path phù hợp

### Lỗi `aws eks get-token` thất bại

Nguyên nhân thường gặp:
- máy chạy thiếu AWS CLI v2
- credentials hiện tại không có quyền với EKS

Cách xử lý:
- cài hoặc nâng cấp AWS CLI v2
- kiểm tra quyền `eks:DescribeCluster` và quyền truy cập cluster theo access entries

### Lỗi Helm release của AWS Load Balancer Controller không lên

Nguyên nhân thường gặp:
- node group chưa sẵn sàng
- Pod Identity chưa map đúng service account
- IAM policy của controller thiếu quyền

Cách xử lý:
- kiểm tra pods trong namespace `kube-system`
- xác nhận service account tên `aws-load-balancer-controller`
- kiểm tra role và Pod Identity association đã tồn tại từ stack `01-infrastructure`

### Lỗi ingress tạo rồi nhưng không sinh ALB

Nguyên nhân thường gặp:
- controller chưa chạy ổn định
- public subnet tags chưa đúng
- annotation trên ingress sai hoặc thiếu

Cách xử lý:
- kiểm tra logs của `aws-load-balancer-controller`
- xác nhận public subnets có tag `kubernetes.io/role/elb`
- kiểm tra lại annotations trong `sample-app.tf`

## 16. Tóm tắt dễ nhớ

`02-platform` là stack đi vào EKS đã có sẵn để cài platform add-on và workload mẫu.

Nó làm 4 việc chính:
1. đọc state của `01-infrastructure`
2. kết nối vào EKS bằng provider Kubernetes và Helm
3. cài AWS Load Balancer Controller
4. tùy chọn tạo sample app + ingress để sinh ALB public
