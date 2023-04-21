# VEP lambda

Deploy VEP as an AWS lambda function.

## Pre-requisites

* AWS environment with requisite permissions
* AWS CLI installed
* AWS authentication set up (using environment variables or profile)
* Docker

## Build and deploy

### Set this var to your AWS ARN

```export AWS_ARN=948922849213```

### Local build and test
```
docker stop $(docker ps -a -q  --filter ancestor=vep-lambda); docker build -t vep-lambda .; docker run -d -p 9000:8080 vep-lambda:latest; curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" -d '{"variants": ["rs699"]}'
```

### Tag and push

Create a repo named `vep-lambda` on AWS ECR via the management console.

Then push to it with the following command:

```
docker tag vep-lambda:latest ${AWS_ARN}.dkr.ecr.eu-west-2.amazonaws.com/vep-lambda/vep-lambda:latest
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin ${AWS_ARN}.dkr.ecr.eu-west-2.amazonaws.com
docker push ${AWS_ARN}.dkr.ecr.eu-west-2.amazonaws.com/vep-lambda/vep-lambda:latest
```

### Create lambda function

NB: added architectures flag as I built the image on my M1 (ARM64) Mac.

```
aws lambda create-function \
    --function-name "vep-lambda" \
    --code ImageUri=${AWS_ARN}.dkr.ecr.eu-west-2.amazonaws.com/vep-lambda:latest \
    --role arn:aws:iam::${AWS_ARN}:role/lambda-custom-runtime-perl-role \
    --package-type Image \
    --architectures arm64
```

### Copy data to S3

Create an S3 bucket named `vep-lambda-data` on AWS management console.

Download and unpack VEP cache locally. This is slow and big, so use HPC on fast network if you can.

Pre-indexed cache files (faster variant data retrieval) can be found in https://ftp.ensembl.org/pub/current_variation/indexed_vep_cache/.

Then copy to S3 with the following:

```
aws s3 cp --sse aws:kms --recursive /path/to/vep-cache/homo_sapiens s3://vep-lambda-data/vep-cache/homo_sapiens
```