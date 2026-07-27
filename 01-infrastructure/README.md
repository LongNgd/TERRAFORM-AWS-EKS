# 01-infrastructure

`01-infrastructure` là stack tạo toàn bộ hạ tầng nền trên AWS cho hệ thống này.
Đây là phần dựng network, EKS, IAM, RDS, S3 và các output mà `02-platform` sẽ dùng tiếp.

Nói ngắn gọn:
- `00-bootstrap` tạo nơi lưu state
- `01-infrastructure` tạo hạ tầng AWS cốt lõi
- `02-platform` cài add-on và workload lên EKS

## 1. Mục đích của `01-infrastructure`

Stack này chịu trách nhiệm tạo các thành phần nền tảng:
- VPC
- public subnets
- private subnets
- Internet Gateway
- NAT Gateway theo từng AZ
- route tables
- S3 Gateway VPC Endpoint
- EKS cluster
- EKS managed node group
- EKS add-ons
- IAM roles và policies
- EKS Pod Identity associations
- RDS PostgreSQL Multi-AZ
- private S3 bucket cho ứng dụng
- security group cho RDS

Đây là stack tạo phần "AWS infrastructure", chưa đụng tới Helm release hay Kubernetes app sample.

## 2. Phạm vi của stack

Stack này chịu trách nhiệm cho lớp hạ tầng AWS cốt lõi:
- network
- compute control plane và worker plane cho EKS
- IAM cho cluster, node và pod
- database
- storage nền tảng

Stack này không cài:
- Helm chart
- Kubernetes namespace, deployment, service, ingress
- workload ứng dụng thật bên trong cluster

## 3. Input và output

### Input chính

| Biến | Bắt buộc | Ý nghĩa ngắn |
| --- | --- | --- |
| `aws_region` | Không | Region triển khai hạ tầng |
| `project_name` | Không | Tên project dùng cho naming và tagging |
| `environment` | Không | Môi trường như `dev`, `staging`, `prod` |
| `cluster_public_access_cidrs` | Có | CIDR được phép truy cập EKS public endpoint |
| `vpc_cidr` | Không | CIDR block của VPC |
| `public_subnet_cidrs` | Không | 2 CIDR cho public subnets |
| `private_subnet_cidrs` | Không | 2 CIDR cho private subnets |
| `availability_zones` | Không | 2 AZ cố định nếu không muốn tự chọn |
| `eks_version` | Không | Minor version của EKS |
| `node_instance_types` | Không | Loại EC2 dùng cho managed node group |
| `node_min_size` | Không | Số node tối thiểu |
| `node_desired_size` | Không | Số node mong muốn |
| `node_max_size` | Không | Số node tối đa |
| `node_capacity_type` | Không | `ON_DEMAND` hoặc `SPOT` |
| `db_engine_version` | Không | Major version của PostgreSQL |
| `db_instance_class` | Không | Instance class của RDS |
| `db_allocated_storage` | Không | Dung lượng storage ban đầu cho RDS |
| `db_max_allocated_storage` | Không | Ngưỡng autoscaling storage tối đa |
| `db_backup_retention_days` | Không | Số ngày giữ automated backups |
| `db_deletion_protection` | Không | Bật/tắt deletion protection cho RDS |
| `db_skip_final_snapshot` | Không | Có bỏ final snapshot khi destroy hay không |
| `app_bucket_name` | Không | Tên S3 bucket app nếu muốn tự đặt |
| `additional_admin_role_arns` | Không | Các IAM role được cấp cluster-admin |

### Output chính

| Output | Ý nghĩa ngắn |
| --- | --- |
| `cluster_name` | Tên EKS cluster để stack sau kết nối |
| `cluster_endpoint` | API endpoint của EKS |
| `cluster_certificate_authority_data` | CA data của cluster |
| `vpc_id` | ID của VPC đã tạo |
| `public_subnet_ids` | Danh sách public subnets |
| `private_subnet_ids` | Danh sách private subnets |
| `rds_endpoint` | Endpoint kết nối PostgreSQL |
| `rds_master_secret_arn` | ARN của secret chứa master password do RDS quản lý |
| `app_bucket_name` | Tên bucket riêng cho ứng dụng |
| `aws_region` | Region của stack này |

Các output này nằm trong `outputs.tf`.

## 4. Luồng chạy tổng thể

Luồng logic:

1. Terraform dùng remote backend S3 từ bucket đã tạo ở `00-bootstrap`.
2. Terraform nạp AWS provider và default tags.
3. Terraform lấy danh sách AZ khả dụng và account ID.
4. Terraform tính các local values như tên project, tên cluster, tên bucket.
5. Terraform tạo VPC, subnets, IGW, NAT Gateway, route tables và S3 VPC endpoint.
6. Terraform tạo KMS key và CloudWatch log group cho EKS.
7. Terraform tạo IAM roles cho EKS cluster, node group, load balancer controller và application pod.
8. Terraform tạo EKS cluster.
9. Terraform tạo managed node group.
10. Terraform cài EKS add-ons mặc định.
11. Terraform tạo Pod Identity associations.
12. Terraform tạo RDS subnet group, security group và PostgreSQL instance.
13. Terraform tạo S3 bucket riêng cho ứng dụng.
14. Terraform xuất output để `02-platform` đọc lại qua remote state.

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
  }
}
```

Ý nghĩa:
- khóa version Terraform CLI theo range cho phép
- khai báo backend `s3` để state nằm trên bucket đã bootstrap
- pin AWS provider `6.56.0`

### `providers.tf`

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
```

Ý nghĩa:
- mọi resource AWS trong stack này chạy ở `var.aws_region`
- toàn bộ resource được gắn `default_tags` từ `local.common_tags`

Mục tiêu:
- quản trị tài nguyên nhất quán
- dễ audit và cost allocation

### `data.tf`

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
```

Ý nghĩa:
- lấy danh sách AZ đang usable trong region
- lấy thông tin account hiện tại để sinh tên bucket hoặc resource theo account ID

### `locals.tf`

Các local chính:
- `name = "${var.project_name}-${var.environment}"`
- `availability_zones`
- `common_tags`
- `cluster_name`
- `app_bucket_name`

Ý nghĩa:
- gom logic dùng lại nhiều nơi vào một chỗ
- giúp tên tài nguyên có quy ước thống nhất

Ví dụ:
- nếu `project_name = "longnd"`
- `environment = "dev"`

thì:
- `local.name = "longnd-dev"`
- `local.cluster_name = "longnd-dev-eks"`

## 6. Giải thích phần network trong `network.tf`

Stack này tạo một VPC trải trên 2 Availability Zones.

### 5.1. VPC

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}
```

Ý nghĩa:
- tạo VPC riêng cho hệ thống
- bật DNS support và DNS hostnames để EKS, RDS và nhiều service AWS hoạt động bình thường

### 5.2. Internet Gateway

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
```

Ý nghĩa:
- cho phép public subnets đi ra Internet

### 5.3. Public subnets

```hcl
resource "aws_subnet" "public" {
  count = 2
  ...
  map_public_ip_on_launch = true
}
```

Ý nghĩa:
- tạo 2 public subnets, mỗi subnet ở 1 AZ
- instance tạo trong đây có thể nhận public IP
- đây là nơi đặt NAT Gateway và ALB public

Tag quan trọng:
- `kubernetes.io/role/elb = "1"`
- `kubernetes.io/cluster/${local.cluster_name} = "shared"`

Ý nghĩa:
- cho AWS Load Balancer Controller biết subnet nào có thể dùng cho internet-facing ALB

### 5.4. Private subnets

```hcl
resource "aws_subnet" "private" {
  count = 2
  ...
}
```

Ý nghĩa:
- tạo 2 private subnets, mỗi subnet ở 1 AZ
- đây là nơi đặt EKS worker nodes và RDS subnet group

Tag quan trọng:
- `kubernetes.io/role/internal-elb = "1"`
- `kubernetes.io/cluster/${local.cluster_name} = "shared"`

Ý nghĩa:
- cho phép dùng internal load balancer nếu cần trong tương lai

### 5.5. Route tables

Stack này tạo:
- 1 public route table có route `0.0.0.0/0` ra Internet Gateway
- 2 private route tables, mỗi cái đi qua 1 NAT Gateway cùng AZ

Ý nghĩa:
- public subnet đi Internet trực tiếp
- private subnet không public, nhưng vẫn có egress ra ngoài qua NAT

### 5.6. NAT Gateway và EIP

```hcl
resource "aws_eip" "nat" {
  count = 2
}

resource "aws_nat_gateway" "main" {
  count = 2
}
```

Ý nghĩa:
- tạo 2 Elastic IP
- tạo 2 NAT Gateway, mỗi NAT nằm trong 1 public subnet

Lợi ích:
- private subnets của từng AZ có đường egress riêng
- giảm single point of failure giữa các AZ

### 5.7. S3 Gateway VPC Endpoint

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
}
```

Ý nghĩa:
- cho private workloads truy cập S3 mà không cần đi ra Internet qua NAT
- giảm chi phí NAT và giảm dependency vào public egress cho traffic S3

## 7. Giải thích phần EKS trong `eks.tf`

### 6.1. KMS key cho secret encryption

```hcl
resource "aws_kms_key" "eks" { ... }
resource "aws_kms_alias" "eks" { ... }
```

Ý nghĩa:
- dùng để mã hóa Kubernetes secrets ở cấp EKS control plane

### 6.2. CloudWatch log group cho EKS control plane logs

```hcl
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 30
}
```

Ý nghĩa:
- giữ log control plane 30 ngày
- phục vụ audit, debug, incident analysis

### 6.3. EKS cluster

```hcl
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version
  ...
}
```

Điểm chính:
- `version = var.eks_version`
- bật control plane logs: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`
- `authentication_mode = "API"`
- `bootstrap_cluster_creator_admin_permissions = true`
- encryption cho `resources = ["secrets"]`
- đặt EKS vào private subnets
- cho phép private endpoint, và có thể cho phép public endpoint tùy biến

Giải thích `vpc_config`:
- `subnet_ids = aws_subnet.private[*].id`
  - cluster dùng private subnets
- `endpoint_private_access = true`
  - VPC nội bộ truy cập API server được
- `endpoint_public_access = var.eks_endpoint_public_access`
  - có thể mở public endpoint nếu cần bootstrap ngoài VPC
- `public_access_cidrs = var.cluster_public_access_cidrs`
  - nếu public endpoint bật, chỉ cho các CIDR này truy cập

### 6.4. Managed node group

```hcl
resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "general"
  ...
}
```

Ý nghĩa:
- tạo node group managed bởi EKS
- node chạy ở private subnets
- dùng AMI `AL2023_x86_64_STANDARD`
- số node lấy từ các biến min/desired/max
- instance types lấy từ `var.node_instance_types`

Điểm đáng chú ý:
- `capacity_type` hỗ trợ `ON_DEMAND` hoặc `SPOT`
- `update_config.max_unavailable = 1`
  - rolling update ở mức an toàn hơn
- có label `workload = "general"`

### 6.5. EKS add-ons

```hcl
locals {
  eks_addons = toset([
    "coredns",
    "eks-pod-identity-agent",
    "kube-proxy",
    "vpc-cni"
  ])
}
```

Và:

```hcl
resource "aws_eks_addon" "main" {
  for_each     = local.eks_addons
  most_recent  = true
  ...
}
```

Ý nghĩa:
- cài các add-on thiết yếu cho EKS
- `most_recent = true` để lấy bản mới nhất tương thích ở thời điểm apply

### 6.6. Pod Identity associations

Có 2 association:
- `aws_eks_pod_identity_association.load_balancer_controller`
- `aws_eks_pod_identity_association.application`

Ý nghĩa:
- service account `aws-load-balancer-controller` trong namespace `kube-system` được assume role tương ứng
- service account `app-sa` trong namespace `app` được assume role ứng dụng

Đây là cách map IAM role cho pod theo cơ chế EKS Pod Identity.

### 6.7. Access entries cho admin roles

```hcl
resource "aws_eks_access_entry" "admin" { ... }
resource "aws_eks_access_policy_association" "admin" { ... }
```

Ý nghĩa:
- cấp cluster-admin cho các role trong `additional_admin_role_arns`
- giúp quản trị quyền vào cluster theo role thay vì chỉ dựa vào người tạo cluster

## 8. Giải thích phần IAM trong `iam.tf`

Stack này tạo 4 nhóm IAM chính:

### 7.1. IAM role cho EKS cluster

- `aws_iam_role.eks_cluster`
- attach `AmazonEKSClusterPolicy`

Ý nghĩa:
- cho control plane EKS quyền cần thiết để quản lý cluster

### 7.2. IAM role cho EKS worker nodes

- `aws_iam_role.eks_node`
- attach:
  - `AmazonEKSWorkerNodePolicy`
  - `AmazonEC2ContainerRegistryPullOnly`
  - `AmazonEKS_CNI_Policy`

Ý nghĩa:
- node có quyền join cluster
- pull image từ ECR
- vận hành network plugin CNI

### 7.3. IAM role cho AWS Load Balancer Controller

- custom policy `aws_iam_policy.load_balancer_controller`
- role `aws_iam_role.load_balancer_controller`
- policy file lấy từ `policies/aws-load-balancer-controller-v3.4.2.json`

Ý nghĩa:
- controller trong cluster có quyền tạo ALB, target group, listener, security group rule và các tài nguyên liên quan

### 7.4. IAM role cho application pod

- role `aws_iam_role.application`
- inline policy `aws_iam_role_policy.application_s3`

Policy này cho phép:
- `s3:ListBucket` trên bucket ứng dụng
- `s3:GetObject`
- `s3:PutObject`
- `s3:DeleteObject`

Ý nghĩa:
- pod ứng dụng có thể thao tác đúng trên bucket riêng của app

## 9. Giải thích phần RDS trong `rds.tf`

### 8.1. DB subnet group

```hcl
resource "aws_db_subnet_group" "main" {
  subnet_ids = aws_subnet.private[*].id
}
```

Ý nghĩa:
- RDS được đặt trong private subnets
- không public ra Internet

### 8.2. PostgreSQL instance

```hcl
resource "aws_db_instance" "postgresql" {
  engine         = "postgres"
  engine_version = var.db_engine_version
  ...
}
```

Điểm chính:
- engine là PostgreSQL
- version major lấy từ `var.db_engine_version`
- dùng storage `gp3`
- bật `storage_encrypted = true`
- `manage_master_user_password = true`
- `publicly_accessible = false`
- `multi_az = true`
- có backup retention
- có maintenance window
- bật `performance_insights_enabled = true`
- export logs `postgresql` và `upgrade`

Điểm quan trọng:
- password master không hardcode trong Terraform variables
- AWS tự quản password trong Secrets Manager
- đây là cách tốt hơn nhiều so với để password trong `.tfvars`

Các biến production-sensitive:
- `db_deletion_protection`
- `db_skip_final_snapshot`

Muốn an toàn production hơn:
- bật deletion protection
- không skip final snapshot

## 10. Giải thích phần security trong `security.tf`

### Security group cho RDS

```hcl
resource "aws_security_group" "rds" { ... }
```

### Ingress rule cho phép PostgreSQL từ EKS cluster security group

```hcl
resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
}
```

Ý nghĩa:
- RDS chỉ cho phép truy cập PostgreSQL từ phía EKS
- không mở public theo CIDR Internet

## 11. Giải thích phần S3 trong `s3.tf`

Stack này tạo 1 bucket riêng cho ứng dụng.

Các đặc điểm chính:
- block public access
- ownership controls = `BucketOwnerEnforced`
- versioning enabled
- server-side encryption mặc định `AES256`
- bucket policy deny nếu dùng insecure transport

Ý nghĩa:
- app bucket là private bucket
- pod trong EKS sẽ truy cập bucket này thông qua IAM role của application pod

## 12. Outputs trong `outputs.tf` dùng để làm gì

### Output cho `02-platform`

- `cluster_name`
  - để provider Kubernetes/Helm biết cluster nào cần kết nối
- `vpc_id`
  - để render Helm values cho load balancer controller
- `public_subnet_ids`
  - để sample ingress chỉ định subnet cho ALB

### Output cho vận hành

- `cluster_endpoint`
  - dùng để debug hoặc kiểm tra kết nối
- `rds_endpoint`
  - nơi ứng dụng sẽ kết nối DB
- `rds_master_secret_arn`
  - ARN secret do RDS quản lý
- `app_bucket_name`
  - tên bucket app cần truy cập

## 13. Luồng apply thực tế

### Bước 1. Chuẩn bị backend

Tạo `backend.hcl` từ file mẫu:

```hcl
bucket       = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
key          = "longnd/dev/infrastructure.tfstate"
region       = "ap-southeast-1"
encrypt      = true
use_lockfile = true
```

### Bước 2. Chuẩn bị tfvars

Ví dụ `terraform.tfvars`:

```hcl
aws_region   = "ap-southeast-1"
project_name = "longnd"
environment  = "dev"

cluster_public_access_cidrs = ["203.0.113.10/32"]

vpc_cidr            = "10.20.0.0/16"
public_subnet_cidrs = ["10.20.0.0/24", "10.20.1.0/24"]
private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]

eks_version         = "1.35"
node_instance_types = ["t3.large"]
node_min_size       = 2
node_desired_size   = 2
node_max_size       = 6
```

### Bước 3. Chạy Terraform

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -out infrastructure.tfplan
terraform apply infrastructure.tfplan
```

### Bước 4. Cấu hình kubectl

```bash
aws eks update-kubeconfig \
  --region ap-southeast-1 \
  --name "$(terraform output -raw cluster_name)"

kubectl get nodes -o wide
```

## 14. Phụ thuộc với stack khác

Phụ thuộc vào `00-bootstrap`:
- cần S3 bucket backend tồn tại trước

Được `02-platform` phụ thuộc vào:
- `02-platform` đọc remote state của stack này
- `02-platform` cần `cluster_name`, `vpc_id`, `public_subnet_ids`

## 15. Điểm tốt của stack này

- tách rõ hạ tầng nền khỏi platform layer
- VPC 2 AZ
- NAT theo từng AZ
- private subnets cho EKS và RDS
- EKS secrets encryption bằng KMS
- bật control plane logs
- RDS Multi-AZ
- password RDS do Secrets Manager quản
- app bucket private và có deny insecure transport
- dùng Pod Identity thay vì hardcode AWS credentials trong pod

## 16. Production checklist

Trước khi dùng stack này cho production, nên kiểm tra các mục sau:

- `cluster_public_access_cidrs` chỉ chứa IP của máy quản trị hoặc CI runner
- cân nhắc đặt `eks_endpoint_public_access = false` nếu có đường chạy Terraform từ trong VPC
- review `bootstrap_cluster_creator_admin_permissions = true` và chuyển dần sang quản trị bằng access entries
- `db_deletion_protection = true`
- `db_skip_final_snapshot = false`
- `db_backup_retention_days` phù hợp RPO của hệ thống
- instance type của node group và RDS đã phù hợp tải thực tế
- có chiến lược patching cho `eks_version`, node group và RDS engine version
- rà lại IAM policy của load balancer controller theo phạm vi VPC/cluster nếu baseline yêu cầu chặt hơn
- xác nhận private subnets, route tables và NAT theo đúng AZ mong muốn
- cân nhắc tách DB subnet tier riêng nếu security baseline yêu cầu
- bổ sung CloudTrail, GuardDuty, VPC Flow Logs, CloudWatch alarms và backup strategy nếu đây là môi trường go-live

## 17. Điểm cần lưu ý trước production

- `db_deletion_protection` mặc định đang `false`
- `db_skip_final_snapshot` mặc định đang `true`
- `eks_endpoint_public_access` mặc định đang `true`
- `bootstrap_cluster_creator_admin_permissions` đang bật
- chưa thấy WAF, CloudTrail, GuardDuty, VPC Flow Logs, backup strategy đầy đủ
- chưa có DB subnet tier tách riêng khỏi private app subnets nếu baseline yêu cầu chặt hơn

## 18. Troubleshooting

### Lỗi `terraform init` với backend S3

Nguyên nhân thường gặp:
- chưa điền đúng `bucket` trong `backend.hcl`
- bucket từ `00-bootstrap` chưa tồn tại
- không đủ quyền đọc ghi state bucket

Cách xử lý:
- kiểm tra lại `backend.hcl`
- xác nhận `00-bootstrap` đã apply thành công
- kiểm tra quyền S3 của AWS profile hoặc IAM role đang dùng

### Lỗi EKS cluster tạo xong nhưng `kubectl get nodes` không thấy node

Nguyên nhân thường gặp:
- node group đang khởi tạo chưa xong
- private subnets hoặc NAT route có vấn đề
- IAM role của node group thiếu policy cần thiết

Cách xử lý:
- chờ thêm vài phút rồi kiểm tra lại
- kiểm tra node group trong AWS Console
- kiểm tra route tables, NAT Gateway, subnet associations
- xác nhận role node đã attach đủ 3 policy cần thiết

### Lỗi không kết nối được EKS API từ ngoài

Nguyên nhân thường gặp:
- `cluster_public_access_cidrs` không chứa IP hiện tại của bạn
- `eks_endpoint_public_access` đang tắt

Cách xử lý:
- kiểm tra lại public IP hiện tại
- cập nhật `cluster_public_access_cidrs`
- nếu cluster private-only, chạy lệnh từ bên trong VPC hoặc bastion/runner phù hợp

### Lỗi RDS không truy cập được từ pod

Nguyên nhân thường gặp:
- pod chưa chạy với service account đúng
- security group hoặc network path chưa đúng
- ứng dụng đang dùng sai endpoint hoặc secret

Cách xử lý:
- xác nhận pod dùng đúng service account nếu cần truy cập tài nguyên AWS
- kiểm tra `rds_endpoint`
- kiểm tra ingress rule từ EKS cluster security group sang RDS security group
- kiểm tra DNS và kết nối TCP 5432 từ pod

## 19. Tóm tắt dễ nhớ

`01-infrastructure` là stack dựng nền AWS thực sự.

Nó làm 5 việc lớn:
1. dựng network
2. dựng EKS
3. dựng IAM cho cluster, pod và controller
4. dựng RDS và app S3 bucket
5. xuất output để `02-platform` cài add-on và workload lên cluster
