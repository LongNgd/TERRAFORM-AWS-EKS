# 00-bootstrap

`00-bootstrap` là bước khởi tạo đầu tiên của toàn bộ repo này.
Nó không tạo EKS, không tạo VPC, không tạo RDS.
Nó chỉ làm một việc: tạo S3 bucket để lưu Terraform remote state cho các stack phía sau.

## 1. Mục đích của `00-bootstrap`

Terraform cần một file state để biết:
- đã tạo những resource nào
- resource đó có ID gì
- lần apply sau cần tạo thêm, sửa hay xóa cái gì

Nếu state chỉ nằm local trên máy:
- khó làm việc nhóm
- khó chạy CI/CD
- dễ mất state
- dễ sinh lệch state giữa nhiều người

Vì vậy repo này dùng:
- `00-bootstrap` để tạo S3 bucket chứa state
- sau đó `01-infrastructure` và `02-platform` sẽ dùng bucket đó làm remote backend

Nói ngắn gọn:
- `00-bootstrap` dựng "kho chứa state"
- `01` và `02` dùng cái kho đó

## 2. Phạm vi của stack

Stack này chỉ xử lý phần remote state bootstrap:
- tạo S3 bucket chứa Terraform state
- áp các cấu hình bảo vệ bucket
- xuất tên bucket để các stack sau dùng làm backend

Stack này không tạo:
- VPC
- EKS
- RDS
- Helm release
- Kubernetes resource

## 3. Input và output

### Input chính

| Biến | Bắt buộc | Ý nghĩa ngắn |
| --- | --- | --- |
| `aws_region` | Không | Region tạo state bucket |
| `project_name` | Không | Tên project dùng để sinh tên bucket và tag |
| `bucket_name` | Không | Tên bucket custom nếu không muốn Terraform tự sinh |

### Output chính

| Output | Ý nghĩa ngắn |
| --- | --- |
| `state_bucket_name` | Tên S3 bucket dùng làm remote backend cho các stack sau |

## 4. Folder này có gì

Các file chính trong `00-bootstrap`:

- `versions.tf`
- `providers.tf`
- `variables.tf`
- `main.tf`
- `outputs.tf`
- `terraform.tfvars.example`

## 5. Luồng chạy tổng thể

Luồng logic:

1. Terraform đọc version yêu cầu.
2. Terraform nạp AWS provider.
3. Terraform đọc biến đầu vào như `aws_region`, `project_name`, `bucket_name`.
4. Terraform gọi AWS để lấy `account_id`.
5. Terraform tính ra tên bucket.
6. Terraform tạo bucket S3.
7. Terraform áp các cấu hình bảo vệ bucket.
8. Terraform output ra tên bucket.
9. Người dùng lấy tên bucket đó điền vào `backend.hcl` của `01-infrastructure` và `02-platform`.

## 6. Giải thích từng file

### `versions.tf`

```hcl
terraform {
  required_version = ">= 1.15.0, < 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.56.0"
    }
  }
}
```

Ý nghĩa:
- `required_version`
  - ép Terraform CLI phải nằm trong range cho phép
  - tránh chạy bằng bản quá cũ hoặc quá mới ngoài kỳ vọng
- `required_providers`
  - khai báo provider AWS
  - pin version `6.56.0`

Mục tiêu:
- giảm rủi ro sai khác môi trường
- đảm bảo code được chạy bằng bộ công cụ đã kiểm soát

### `providers.tf`

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
      Stack     = "bootstrap"
    }
  }
}
```

Ý nghĩa:
- `provider "aws"`
  - nói cho Terraform biết sẽ thao tác với AWS
- `region = var.aws_region`
  - bucket sẽ được tạo trong region này
- `default_tags`
  - mọi resource do provider này tạo sẽ được gắn tag mặc định:
    - `Project`
    - `ManagedBy`
    - `Stack`

Lợi ích:
- dễ quản trị tài nguyên
- dễ filter theo project/stack
- thuận tiện cho audit, cost allocation, governance

### `variables.tf`

```hcl
variable "aws_region" {
  type        = string
  description = "AWS Region used for the Terraform state bucket."
  default     = "ap-southeast-1"
}

variable "bucket_name" {
  type        = string
  description = "Optional globally unique S3 bucket name. Leave empty to derive it from project, account, and Region."
  default     = ""
}

variable "project_name" {
  type        = string
  description = "Project identifier used in resource names and tags."
  default     = "longnd"
}
```

Ý nghĩa từng biến:

- `aws_region`
  - region để tạo state bucket
  - mặc định là `ap-southeast-1`

- `bucket_name`
  - nếu bạn muốn tự đặt tên bucket thì điền vào đây
  - nếu để rỗng, Terraform sẽ tự sinh tên

- `project_name`
  - dùng để sinh tên bucket mặc định
  - đồng thời dùng làm tag

### `outputs.tf`

```hcl
output "state_bucket_name" {
  description = "S3 bucket used by the infrastructure and platform stacks."
  value       = aws_s3_bucket.terraform_state.id
}
```

Ý nghĩa:
- xuất tên bucket sau khi apply
- output này sẽ được copy sang:
  - `01-infrastructure/backend.hcl`
  - `02-platform/backend.hcl`

Ví dụ:

```bash
terraform output -raw state_bucket_name
```

sẽ trả về kiểu như:

```text
longnd-tfstate-123456789012-ap-southeast-1
```

## 7. Giải thích đầy đủ `main.tf`

### 5.1. Lấy account ID hiện tại

```hcl
data "aws_caller_identity" "current" {}
```

Đây là `data source`, không tạo resource mới.
Nó gọi AWS để lấy thông tin identity hiện tại đang chạy Terraform, trong đó có:
- account ID
- ARN
- user/role context

Trong folder này, mục đích chính là lấy:
- `data.aws_caller_identity.current.account_id`

Tại sao cần?
- vì tên bucket S3 phải unique toàn cục
- thêm `account_id` vào tên bucket giúp giảm khả năng trùng tên

### 5.2. Tính tên bucket

```hcl
locals {
  state_bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}
```

Ý nghĩa:
- nếu `var.bucket_name` khác rỗng:
  - dùng tên do người dùng chỉ định
- nếu `var.bucket_name` rỗng:
  - tự sinh tên theo format:
    - `${project_name}-tfstate-${account_id}-${region}`

Ví dụ:
- `project_name = "longnd"`
- `account_id = "123456789012"`
- `aws_region = "ap-southeast-1"`

thì bucket name sẽ là:

```text
longnd-tfstate-123456789012-ap-southeast-1
```

Lợi ích:
- không phải hardcode tên bucket
- giảm đụng tên với người khác
- dễ nhận diện bucket này thuộc project nào

### 5.3. Tạo S3 bucket

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = local.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}
```

Đây là resource tạo bucket S3 thật sự.

Giải thích:
- `bucket = local.state_bucket_name`
  - dùng tên bucket đã tính ở bước trên

- `lifecycle.prevent_destroy = true`
  - chặn Terraform xóa bucket này bằng các thao tác thông thường
  - nếu ai đó chạy `terraform destroy`, Terraform sẽ báo lỗi thay vì xóa bucket

Tại sao rất quan trọng?
- bucket này chứa Terraform state
- nếu xóa nhầm state bucket:
  - bạn không mất tài nguyên AWS ngay lập tức
  - nhưng mất file state, tức là mất "bản đồ quản lý hạ tầng"
  - hậu quả là Terraform rất khó quản lý tiếp chính xác

Hiểu đơn giản:
- bucket là "kho"
- `prevent_destroy` là "khóa chống đập kho"

### 5.4. Cấu hình ownership của object trong bucket

```hcl
resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
```

Resource này cấu hình quyền sở hữu object trong bucket.

Giải thích:
- `bucket = aws_s3_bucket.terraform_state.id`
  - áp cấu hình này cho bucket vừa tạo

- `object_ownership = "BucketOwnerEnforced"`
  - bucket owner sẽ là owner của object
  - đồng thời ACL bị vô hiệu hóa

Ý nghĩa thực tế:
- không dùng ACL kiểu cũ
- quản lý quyền bằng IAM và bucket policy thay vì ACL
- giảm các lỗi khó hiểu về ownership hoặc permission

Với state bucket, đây là cách làm rất hợp lý vì:
- state không cần public
- không cần chia quyền bằng ACL
- muốn mọi thứ nằm dưới quyền kiểm soát rõ ràng của account sở hữu bucket

### 5.5. Chặn public access

```hcl
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

Resource này khóa bucket khỏi các tình huống public ngoài ý muốn.

Từng thuộc tính:

- `block_public_acls = true`
  - chặn việc gán ACL public cho bucket hoặc object

- `block_public_policy = true`
  - chặn việc áp bucket policy public

- `ignore_public_acls = true`
  - nếu đâu đó có public ACL, S3 bỏ qua luôn

- `restrict_public_buckets = true`
  - nếu bucket policy bị xem là public, S3 sẽ siết truy cập lại

Tại sao quan trọng?
- Terraform state rất nhạy cảm
- state có thể chứa:
  - IDs tài nguyên
  - endpoint
  - topology hạ tầng
  - giá trị nhạy cảm nếu cấu hình không cẩn thận

Nếu bucket state bị public thì đó là lỗi bảo mật nghiêm trọng.

### 5.6. Bật versioning

```hcl
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

Resource này bật versioning cho bucket.

Ý nghĩa:
- mỗi lần file state bị ghi đè, S3 giữ lại version cũ
- nếu state bị hỏng hoặc cập nhật sai, còn cơ hội khôi phục thủ công

Tại sao rất quan trọng với Terraform?
- `terraform.tfstate` bị thay đổi gần như sau mỗi lần apply
- nếu không có versioning:
  - state mới ghi đè state cũ
  - lỡ có lỗi thì khó quay lại
- nếu có versioning:
  - còn lịch sử object version

Đây là một best practice gần như bắt buộc với remote state trên S3.

### 5.7. Bật mã hóa mặc định cho object

File này còn có thêm đoạn:

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

Ý nghĩa:
- mọi object ghi vào bucket sẽ được mã hóa server-side mặc định
- `AES256` là S3-managed encryption

Lợi ích:
- tăng bảo vệ dữ liệu at rest
- phù hợp hơn nhiều so với bucket không mã hóa

Lưu ý:
- đây là mức tốt
- production nghiêm hơn thường cân nhắc `aws:kms` để kiểm soát khóa chi tiết hơn

## 8. Các resource này phối hợp với nhau như thế nào

Trình tự logic:

1. `aws_s3_bucket`
   - tạo bucket vật lý
2. `aws_s3_bucket_ownership_controls`
   - quy định bucket owner là owner của object
   - loại bỏ phụ thuộc vào ACL
3. `aws_s3_bucket_public_access_block`
   - khóa public access
4. `aws_s3_bucket_versioning`
   - bật lịch sử version object
5. `aws_s3_bucket_server_side_encryption_configuration`
   - bật mã hóa mặc định

Nói cách khác:
- resource đầu tiên tạo "container"
- các resource sau làm cho container đó an toàn và phù hợp để chứa state

## 9. Luồng apply thực tế

### Bước 1. Chuẩn bị biến

Từ `00-bootstrap/terraform.tfvars.example` tạo file `terraform.tfvars`.

Ví dụ:

```hcl
aws_region   = "ap-southeast-1"
project_name = "longnd"
# bucket_name = "my-custom-unique-tfstate-bucket"
```

Nếu không set `bucket_name`, Terraform tự sinh tên bucket.

### Bước 2. Init

```bash
terraform init
```

Ý nghĩa:
- tải provider AWS theo version khai báo
- chuẩn bị working directory để chạy Terraform

### Bước 3. Validate

```bash
terraform validate
```

Ý nghĩa:
- kiểm tra syntax và cấu trúc Terraform hợp lệ

### Bước 4. Plan

```bash
terraform plan -out bootstrap.tfplan
```

Ý nghĩa:
- xem Terraform dự định tạo gì
- ở đây chủ yếu là 1 bucket và các cấu hình đi kèm

### Bước 5. Apply

```bash
terraform apply bootstrap.tfplan
```

Ý nghĩa:
- tạo bucket thật trên AWS

### Bước 6. Lấy output

```bash
terraform output -raw state_bucket_name
```

Kết quả là tên bucket vừa tạo.

### Bước 7. Dùng output cho các stack sau

Điền bucket này vào:

`01-infrastructure/backend.hcl`

```hcl
bucket       = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
key          = "longnd/dev/infrastructure.tfstate"
region       = "ap-southeast-1"
encrypt      = true
use_lockfile = true
```

`02-platform/backend.hcl`

```hcl
bucket       = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
key          = "longnd/dev/platform.tfstate"
region       = "ap-southeast-1"
encrypt      = true
use_lockfile = true
```

Ý nghĩa:
- cả `01` và `02` đều dùng chung bucket
- nhưng mỗi stack có `key` khác nhau
- tức là mỗi stack có state file riêng

## 10. Phụ thuộc với stack khác

Stack này không phụ thuộc vào `01-infrastructure` hay `02-platform`.

Ngược lại:
- `01-infrastructure` phụ thuộc vào bucket backend mà stack này tạo ra
- `02-platform` cũng phụ thuộc vào cùng bucket backend đó

## 11. `00-bootstrap` tạo xong thì được gì

Sau khi chạy xong, bạn có:
- một state bucket trên S3
- bucket có:
  - chống xóa nhầm
  - chặn public access
  - versioning
  - encryption
  - ownership control tốt hơn mặc định

Từ lúc đó:
- `01-infrastructure` có thể dùng remote backend
- `02-platform` có thể dùng remote backend

## 12. Điểm tốt của stack này

Phần này làm khá đúng hướng vì đã có:

- `prevent_destroy`
  - tránh xóa nhầm state bucket

- `public_access_block`
  - tránh lộ state

- `BucketOwnerEnforced`
  - bỏ ACL, quản lý quyền rõ hơn

- `versioning`
  - giữ lịch sử state

- `server-side encryption`
  - bảo vệ dữ liệu at rest

Đây là một nền tảng ổn cho state bucket.

## 13. Production checklist

Trước khi dùng stack này cho production, nên kiểm tra các mục sau:

- `S3 bucket` đã bật `versioning`
- `S3 bucket` đã bật `server-side encryption`
- `S3 bucket` đã bật `public access block`
- `S3 bucket` đang dùng `prevent_destroy`
- bucket name đã đủ rõ ràng và unique theo account/region
- backend của các stack sau đã bật `use_lockfile = true`
- cân nhắc đổi `AES256` sang `aws:kms` nếu tổ chức yêu cầu CMK
- cân nhắc thêm bucket policy bắt buộc TLS
- cân nhắc thêm lifecycle rule cho các version cũ của state
- cân nhắc bật logging hoặc audit cho bucket nếu baseline yêu cầu
- commit `.terraform.lock.hcl` sau khi init để tăng tính tái lập giữa local và CI

## 14. Điểm chưa phải mức production cứng nhất

`00-bootstrap` tốt, nhưng chưa phải hardening tối đa.

Một số điểm có thể nâng thêm:

- dùng `aws:kms` thay cho `AES256`
  - nếu cần kiểm soát key, audit, rotation sâu hơn

- thêm bucket policy bắt buộc TLS
  - chặn request không dùng HTTPS

- thêm lifecycle rule cho old object versions
  - tránh versioning tăng dung lượng mãi

- thêm logging/audit
  - nếu tổ chức yêu cầu kiểm toán chặt

- commit `.terraform.lock.hcl`
  - để reproducible hơn giữa local và CI

## 15. Troubleshooting

### Lỗi `BucketAlreadyExists` hoặc `BucketAlreadyOwnedByYou`

Nguyên nhân thường gặp:
- tên bucket bị trùng toàn cục
- bạn đã từng tạo bucket đó trước đây

Cách xử lý:
- đặt `bucket_name` khác
- hoặc đổi `project_name`
- hoặc kiểm tra lại bucket đã tồn tại trong account hiện tại chưa

### Lỗi không xóa được bucket khi destroy

Nguyên nhân thường gặp:
- bucket có `prevent_destroy = true`
- bucket vẫn còn object hoặc version object

Cách xử lý:
- xác nhận bạn thực sự muốn xóa state bucket
- dọn toàn bộ object và object versions trong bucket
- chỉ bỏ `prevent_destroy` khi thực sự cần và đã hiểu rủi ro

### Lỗi access denied khi tạo bucket hoặc áp policy

Nguyên nhân thường gặp:
- IAM role hoặc AWS profile đang dùng không đủ quyền với S3

Cách xử lý:
- kiểm tra quyền `s3:CreateBucket`, `s3:PutBucketVersioning`, `s3:PutBucketEncryption`, `s3:PutBucketPublicAccessBlock`
- kiểm tra lại account và region đang chạy

## 16. Tóm tắt dễ nhớ

`00-bootstrap` là bước dựng kho state trung tâm cho Terraform.

Nó làm 3 việc chính:
1. tạo S3 bucket
2. làm bucket đó an toàn hơn
3. xuất tên bucket để stack khác dùng làm backend

Nếu không có bước này:
- `01-infrastructure` và `02-platform` không có remote state chuẩn để chạy
