# VEP lambda

Deploy VEP as an AWS lambda function.

## Build and deploy

### Set this var to your AWS ARN

```export AWS_ARN=948922849213```

### Local build and test
```
docker stop $(docker ps -a -q  --filter ancestor=vep-lambda); docker build -t vep-lambda .; docker run -d -p 9000:8080 vep-lambda:latest; curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" -d '{"variants": ["rs699"]}'
```

### Tag and push

Create a repo named `vep-lambda` on AWS ECR via the management console.

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
