# WordPress - Helm Chart for Kubernetes

## Introduction
This Helm chart installs WordPress in a Kubernetes cluster with many advanced features. It is based on the official WordPress image and provides automation for installation, user management, plugin installation, and metrics for prometheus (WordPress and Apache).

## TL;DR

Install with helm
```bash
helm install wordpress oci://ghcr.io/slybase/charts/wordpress
```

> **Note:** Soon only OCI registries will be supported. Please migrate to this OCI-based installation method shown above.


## Default installation of WordPress Information

By default this chart does not install any WordPress themes or preconfigure plugins for the frontend. After the chart is deployed you must log in to the WordPress admin (wp-admin) and set up the first theme and any desired plugins.

## Features

### Automatic WordPress Installation
- **Init Container**: Automatic initial installation of WordPress with predefined admin credentials.
- **Configuration**: Set admin username, password, email, first name, last name, and blog title.
- **Debug Mode**: Enable debugging for the installation.
- **Permalinks**: Configure permalink structures (e.g., postName, dayAndName).

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
  - See details on GitHub Repo of (SlyMetrics Plugin from slydalke)[https://github.com/slydlake/slymetrics] 
- **Apache Metrics**: Sidecar container for Apache metrics.
  - See details on GitHub Repo of (apache exporter from Lusitaniaes)[https://github.com/Lusitaniae/apache_exporter]
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
- By default `mariadb.enabled` is true. you have to set `mariadb.auth` and `mariadb.persistence`. Alternatively, it is also possible to use an external database.

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
```bash
helm install my-wordpress slycharts/wordpress
```

### With External Database
```bash
helm install my-wordpress slycharts/wordpress \
  --set externalDatabase.host=your-db-host \
  --set externalDatabase.username=your-user \
  --set externalDatabase.password=your-password \
  --set externalDatabase.database=your-db
```

### With Metrics
```bash
helm install my-wordpress slycharts/wordpress \
  --set metrics.wordpress.enabled=true \
  --set metrics.apache.enabled=true
```

## Support

For issues or contributions: [GitHub Repository](https://github.com/slydlake/helm-charts)
