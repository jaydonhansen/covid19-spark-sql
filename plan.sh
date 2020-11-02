terraform init && \
terraform plan -var bucket_name_dp=infs3208_spark_bucket \
               -var bq_dataset=spark_dataset \
               -var bq_dataset_name=Spark \
               -var cluster_dp_name=dataproc-cluster \
               -var cluster_location=us-central1 \
               -var project=infs3208-287704 \
               -var worker_num_instances=2 \
               -out "run.plan"
