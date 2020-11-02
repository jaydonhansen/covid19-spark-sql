// Bucket to stage files to before writing out to a database
resource "google_storage_bucket" "tstdataprocbuck" {
  name          = var.bucket_name_dp
  location      = lookup(var.dataprocbuckloc, var.cluster_location)
  force_destroy = "true"
}

// Dataproc Cluster
resource "google_dataproc_cluster" "tstdataprocclus" {
  name   = var.cluster_dp_name
  region = var.cluster_location

  labels = {
    foo = "bar"
  }

  cluster_config {
    staging_bucket = google_storage_bucket.tstdataprocbuck.name

    master_config {
      // Take the config from the variables specified in the Plan
      num_instances    = var.master_num_instances
      machine_type     = var.master_machine_type
      min_cpu_platform = "Intel Skylake"

      disk_config {
        boot_disk_type    = "pd-ssd"
        boot_disk_size_gb = 50
      }
    }

    worker_config {
      num_instances    = var.worker_num_instances
      machine_type     = var.worker_machine_type
      min_cpu_platform = "Intel Skylake"

      disk_config {
        boot_disk_size_gb = 50
        num_local_ssds    = 0
      }
    }

    preemptible_worker_config {
      num_instances = 0
    }

    software_config {
      image_version = "1.3.72-debian10"

      override_properties = {
        "dataproc:dataproc.allow.zero.workers"        = "true"
        "dataproc:dataproc.conscrypt.provider.enable" = "false"
      }
    }

    gce_cluster_config {
      network = google_compute_network.dataproc_network.name
      tags    = ["cluster"]
    }
    // Install Presto for databse integration
    initialization_action {
      script      = "gs://dataproc-initialization-actions/presto/presto.sh"
      timeout_sec = 500
    }

    // Install Jupyter notebook
    initialization_action {
      script      = "gs://dataproc-initialization-actions/jupyter/jupyter.sh"
      timeout_sec = 500
    }
  }

  depends_on = [google_storage_bucket.tstdataprocbuck]

  // Timeout if can't create within 30 minutes.
  timeouts {
    create = "30m"
    delete = "30m"
  }
}

# Submit a test spark job to a Dataproc cluster
resource "google_dataproc_job" "spark" {
  region       = google_dataproc_cluster.tstdataprocclus.region
  force_delete = true

  placement {
    cluster_name = google_dataproc_cluster.tstdataprocclus.name
  }

  spark_config {
    main_class    = "org.apache.spark.examples.SparkPi"
    jar_file_uris = ["file:///usr/lib/spark/examples/jars/spark-examples.jar"]
    args          = ["1000"]

    properties = {
      "spark.logConf" = "true"
    }

    logging_config {
      driver_log_levels = {
        "root" = "INFO"
      }
    }
  }
}

# Submit the COVID-19 pyspark job to the dataproc cluster
resource "google_dataproc_job" "pyspark_covid19" {
  region       = google_dataproc_cluster.tstdataprocclus.region
  force_delete = true

  placement {
    cluster_name = google_dataproc_cluster.tstdataprocclus.name
  }

  pyspark_config {
    main_python_file_uri = "gs://infs3208-spark-data/spark_sql_query.py"
    jar_file_uris = ["gs://spark-lib/bigquery/spark-bigquery-latest.jar"]

    properties = {
      "spark.logConf" = "true"
    }
  }
}

resource "google_bigquery_dataset" "default" {
  dataset_id                  = var.bq_dataset
  friendly_name               = var.bq_dataset_name
  description                 = "This is a test description"
  location                    = lookup(var.dataprocbuckloc, var.cluster_location)
  default_table_expiration_ms = 3600000

  labels = {
    env = "default"
  }
}

resource "google_bigquery_table" "default" {
  dataset_id = google_bigquery_dataset.default.dataset_id
  table_id   = "test"

  time_partitioning {
    type = "DAY"
  }

  labels = {
    env = "default"
  }

  schema = file("schema.json")
}

# Check out current state of the jobs
output "BigQuery_dataset_status" {
  value = google_bigquery_table.default.dataset_id
}
output "google_bucket_status" {
  value = google_storage_bucket.tstdataprocbuck.url
}

output "dataproc_cluster_status" {
  value = google_dataproc_cluster.tstdataprocclus.id
}
output "dataproc_master_status" {
  value = google_dataproc_cluster.tstdataprocclus.cluster_config.0.master_config.0.instance_names
}
output "dataproc_worker_status" {
  value = google_dataproc_cluster.tstdataprocclus.cluster_config.0.worker_config.0.instance_names
}
output "spark_status" {
  value = google_dataproc_job.spark.status.0.state
}

output "pyspark_covid19status" {
  value = google_dataproc_job.pyspark_covid19.status.0.state
}

output "logs_directory_browser_url" {

  value       = join("", google_storage_bucket.tstdataprocbuck.*.url)
  description = "The base URL of the bucket, in the format gs://<bucket-name>"
}
