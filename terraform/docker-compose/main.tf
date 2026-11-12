resource "google_compute_instance" "cloud_vm" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
    }
  }

  network_interface {
    network = "default"

    access_config {}
  }

  metadata_startup_script = file("${path.module}/startup.sh")

  tags = ["http-server", "https-server"]
}

# Firewall
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}
