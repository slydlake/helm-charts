# WordPress - Helm Chart for Kubernetes

## Introduction
This Helm chart installs WordPress in a Kubernetes cluster with many advanced features. It is based on the official WordPress image and provides automation for installation, user management, plugin installation, and metrics for prometheus (WordPress and Apache).

> **Note:** Soon only OCI registries will be supported. Please migrate to this OCI-based installation method shown below.

## TL;DR

You can find different sample YAML files (external database, integrated MariaDB and advanced configuration) in the GitHub repo in the subfolder "samples".

> **Note:** No theme will be installed. You have to log in to /wp-admin to install a theme.


### Installation with integrated MariaDB chart

```yaml
# ./samples/mariaDB.secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: wordpress-test-secret
stringData:
  mariadb-root-password: S3cureDBP@ss
  mariadb-password: Sup3rS3cureP@ss
type: Opaque

```

```yaml
# ./samples/mariaDB.values.yaml
wordpress:
  url: "https://example.com"
mariadb:
  auth:
    database: "wordpress_db"
    username: "wordpress_db_user"
    existingSecret: "wordpress-test-secret"
```

Install with Helm:
```bash
kubectl apply -f ./samples/mariaDB.secrets.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/mariaDB.values.yaml
```

## Features

### Automatic WordPress Installation
- **Init Container**: Automatic initial installation of WordPress with predefined admin credentials.
- **Configuration**: Set admin username, password, email, first name, last name, and blog title.
- **Debug Mode**: Enable debugging for the installation.
- **Permalinks**: Configure permalink structures (e.g., post name, day and name).

### User Management
- **Automatic User Generation**: Create additional users with roles (Administrator, Editor, etc.).
- **Email Notification**: Automatically send emails with generated passwords.

### Language
- **Language**: Set the WordPress language (e.g., de_DE for German).

### Plugin Installation
- **Automatic Installation**: Install plugins from WordPress.org, local ZIPs, or URLs.
- **Versioning**: Specify plugin versions.
- **Activation and Auto-Updates**: Activate plugins after installation and enable auto-updates.

### Database
- **External Database**: Use an external MariaDB/MySQL database.
- **Embedded MariaDB**: Enable the integrated MariaDB chart for local database.
- **Memcached**: Enable Memcached for caching.

### Metrics and Monitoring
- **WordPress Metrics**: Automatically install a WordPress Plugin for Prometheus metrics.
  - See details on GitHub Repo of (SlyMetrics Plugin from slydlake)[https://github.com/slydlake/slymetrics] 
- **Apache Metrics**: Sidecar container for Apache metrics.
  - See details on GitHub Repo of (apache exporter from Lusitaniae)[https://github.com/Lusitaniae/apache_exporter]
- **Grafana Dashboard**: Integrate with Grafana for metrics visualization.


### Additional Configuration Files in values
- **Custom wp-config.php**: Additional constants like WP_MEMORY_LIMIT.
- **.htaccess Configuration**: Customize Apache URL rewriting and directives via `wordpress.htaccess`.
- **Apache Default Site Config**: Modify `/etc/apache2/sites-available/000-default.conf` using `apache.customDefaultSiteConfig`.
- **Apache Ports Config**: Adjust `/etc/apache2/ports.conf` with `apache.customPortsConfig`.
- **Apache PHP Config**: Set PHP settings like upload limits via `apache.customPhpConfig`.


## Security by default

- **Pod Security Context**: Configured by default for secure permissions.
- **Container Security Context**: RunAsNonRoot and additional security measures enabled.


## Configuration

### Mandatory parameters
- `wordpress.url`: Is needed to set wp-config with correct settings
- `storage`: Set your storage settings for WordPress
- By default `mariadb.enabled` is true. You have to set `mariadb.auth` and `mariadb.persistence`. Alternatively, it is also possible to use an external database.

### Recommended parameters
- `wordpress.init`: Admin credentials and blog setup
- `service.type`: If you want to access WordPress internally set it to NodePort

### Additional parameters
- `wordpress.plugins`: List of plugins to install
- `wordpress.users`: Additional users
- `wordpress.language`: Language (e.g., de_DE)
- `wordpress.permalinks.structure`: Set the wordpress post structure
- `metrics.wordpress`: Enable WordPress metrics
- `metrics.apache`: Enable Apache metrics
- `memcached.enabled`: Enable embedded memcached


## Installation

### Basic Installation
See in TL;DR

### With External Database
Find the externalDB.secrets.yaml and externalDB.values.yaml in the GitHub repo in the subfolder "samples".

```bash
kubectl apply -f ./samples/externalDB.secrets.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/externalDB.values.yaml
```

### Advanced installation
Find the advanced.secrets.yaml, advanced.configmap.yaml and advanced.values.yaml in the GitHub repo in the subfolder "samples".

This includes:
* Initial setup of WordPress
* Plugin Installation
* Additional WordPress user
* Additional configuration files
  * .htaccess
  * wp-config.php settings
  * apache custom.ini
* Permanent Nodeport
* Prometheus metrics
  * For WordPress
  * For Apache
* Memcached pod 

```bash
kubectl apply -f ./samples/advanced.secrets.yaml
kubectl apply -f ./samples/advanced.configmap.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/advanced.values.yaml
```

## Support

For issues or contributions: [GitHub Repository](https://github.com/slydlake/helm-charts)
