# WordPress - Helm Chart for Kubernetes

## Introduction
This Helm chart installs WordPress in a Kubernetes cluster with many advanced features. It is based on the official WordPress image and provides automation for installation, user management, plugin installation, and metrics for prometheus (WordPress and Apache).

## TL;DR

You can find different sample YAML files (external database, integrated MariaDB and advanced configuration) in the GitHub repo in the subfolder "samples".

> **Note:** No default site is set as "Home", so you will see no landing page. You have to log in to /wp-admin to install a theme.


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
- **Automatic Installation**: Install plugins from WordPress.org, local ZIPs, URLs, or Composer packages.
- **Composer Support**: Install plugins via Composer (e.g., `humanmade/s3-uploads`) that aren't available in WordPress.org.
- **Versioning**: Specify plugin versions (WordPress.org and Composer syntax supported).
- **Activation and Auto-Updates**: Activate plugins after installation and enable auto-updates.

### Theme Installation
- **Automatic Installation**: Install themes from WordPress.org, local ZIPs, URLs, or Composer packages.
- **Composer Support**: Install themes via Composer (e.g., `wpackagist-theme/astra`).
- **Versioning**: Specify theme versions (WordPress.org and Composer syntax supported).
- **Activation and Auto-Updates**: Activate themes after installation and enable auto-updates.
- **Custom Themes**: Support for custom theme ZIPs via direct URLs.

### Database
- **External Database**: Use an external MariaDB/MySQL database.
- **Embedded MariaDB**: Enable the integrated MariaDB chart for local database.
- **Memcached**: Enable Memcached for caching.

### Metrics and Monitoring
- **WordPress Metrics**: Automatically install a WordPress Plugin for Prometheus metrics.
  - See details on GitHub Repo of (SlyMetrics Plugin from slydlake)[https://github.com/slydlake/slymetrics]
- **Apache Metrics**: Sidecar container for Apache metrics.
  - See details on GitHub Repo of (apache exporter from Lusitaniae)[https://github.com/Lusitaniae/apache_exporter]
- **Grafana Dashboard**: Automatically deploy Grafana dashboard for WordPress metrics visualization.
  - Requires Grafana with dashboard sidecar (e.g., kube-prometheus-stack)
  - Automatically discovered via `grafana_dashboard: "1"` labe


### Additional Configuration Files in values
- **Custom wp-config.php**: Additional constants like WP_MEMORY_LIMIT.
- **.htaccess Configuration**: Customize Apache URL rewriting and directives via `wordpress.htaccess`.
- **Apache Default Site Config**: Modify `/etc/apache2/sites-available/000-default.conf` using `apache.customDefaultSiteConfig`.
- **Apache Ports Config**: Adjust `/etc/apache2/ports.conf` with `apache.customPortsConfig`.
- **Apache PHP Config**: Set PHP settings like upload limits via `apache.customPhpConfig`.

### Custom commands in init container
- **Execute custom shell commands** after init.sh via ConfigMap (`wordpress.init.customInitConfigMap.name`)
- Perfect for custom setup tasks like updating plugins or creating pages
- Configure with `name` and optional `key` (defaults to "commands.sh")
- See `samples/customInit.configmap.yaml` and `samples/customInit.values.yaml`

### MU-Plugins (Must-Use Plugins)
- **Deploy MU-Plugins via ConfigMaps** - automatically activated PHP code that cannot be deactivated
- Each ConfigMap data key becomes a PHP file in `wp-content/mu-plugins/`
- Reference multiple ConfigMaps in `wordpress.muPluginsConfigMaps`
- See `samples/muPlugins.configmap.yaml` and `samples/muPlugins.values.yaml`


## Security by default

- **Pod Security Context**: Configured by default for secure permissions.
- **Container Security Context**: RunAsNonRoot and additional security measures enabled.


## WordPress configuration

### Mandatory parameters
- `wordpress.url`: Is needed to set wp-config with correct settings
- `storage`: Set your storage settings for WordPress
- By default `mariadb.enabled` is true. You have to set `mariadb.auth` and `mariadb.persistence`. Alternatively, it is also possible to use an external database.

### Recommended parameters
- `wordpress.init`: Admin credentials and blog setup
- `service.type`: If you want to access WordPress internally set it to NodePort

### Additional parameters
- `wordpress.plugins`: List of plugins to install
- `wordpress.themes`: List of themes to install
- `wordpress.users`: Additional users
- `wordpress.language`: Language (e.g., de_DE)
- `wordpress.permalinks.structure`: Set the wordpress post structure
- `metrics.wordpress`: Enable WordPress metrics
- `metrics.apache`: Enable Apache metrics
- `memcached.enabled`: Enable embedded memcached


## Installation samples

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

This includes everything from basic installation plus:
* **Initial setup of WordPress**
* **Plugin Installation**
* **Theme Installation**
* **Additional WordPress user**
* **Additional configuration files**
  * .htaccess
  * wp-config.php settings
  * apache custom.ini
* **Permanent Nodeport**
* **Prometheus metrics**
  * For WordPress
  * For Apache
* **Memcached pod**

```bash
kubectl apply -f ./samples/advanced.secrets.yaml
kubectl apply -f ./samples/advanced.configmap.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/advanced.values.yaml
```

### Advanced installation with High Availability (2 Replicas)
Find the advanced2.values.yaml in the GitHub repo in the subfolder "samples".

This setup includes everything from the advanced installation plus:
* **2 WordPress pod replicas** for high availability and load balancing
* **ReadWriteMany (RWX) storage** to allow multiple pods to share the same WordPress files
* **Distributed locking** ensures only one pod runs init operations at a time (prevents race conditions)

**Requirements:**
* Your cluster must support ReadWriteMany (RWX) storage class (e.g., NFS, Ceph, cloud provider shared storage)
* LoadBalancer or Ingress for distributing traffic across replicas

```bash
kubectl apply -f ./samples/advanced.secrets.yaml
kubectl apply -f ./samples/advanced.configmap.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/advanced2.values.yaml
```

### Custom Init Commands
Execute custom shell commands after WordPress installation. See `samples/customInit.configmap.yaml` and `samples/customInit.values.yaml`.

```bash
kubectl apply -f ./samples/customInit.configmap.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/customInit.values.yaml
```

### MU-Plugins via ConfigMaps
Deploy Must-Use Plugins that are automatically activated. See `samples/muPlugins.configmap.yaml` and `samples/muPlugins.values.yaml`.

```bash
kubectl apply -f ./samples/muPlugins.configmap.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/muPlugins.values.yaml
```

### Composer Packages
Install plugins and themes via Composer that aren't available in WordPress.org. See `samples/composer.values.yaml`.

```bash
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/composer.values.yaml
```

**Examples:**
- **Plugins**: `humanmade/s3-uploads`, `wpackagist-plugin/wordpress-seo`
- **Themes**: `wpackagist-theme/astra`
- **Auto-Update**: Works for packages without fixed version (always installs latest)
- **Pruning**: Compatible with `pluginsPrune` and `themesPrune`

#### Custom Composer Repositories
By default, only **wpackagist.org** is configured, which mirrors all WordPress.org plugins and themes.

Add custom repositories for private/premium packages:

```yaml
wordpress:
  composer:
    repositories:
      - type: "vcs"
        url: "https://github.com/mycompany/private-plugin"
      - type: "composer"
        url: "https://my-satis-server.com"
      - type: "package"
        package:
          name: "vendor/premium-plugin"
          version: "1.0.0"
          dist:
            url: "https://example.com/premium-plugin.zip"
            type: "zip"
  plugins:
    - name: "mycompany/private-plugin"
      activate: true
```

## Notable changes

### To 2.0.0
- WordPress version from 6.8.3 to 6.9.0
- WordPress image tag from PHP version 8.1 to 8.3 (default)
- mariadb from 12.0.2 to 12.1.2

### To 1.0.0
This major release introduces new possibilities to use composer plugins and themes and muPlugins. Now it is possible to activate a prune mode for plugins and themes. This will uninstall all plugins/themes that are not listed in the values.

Also adds more flexible user customization with init scripts. The init script is now a huge set to pre-configure and set up WordPress.
For more, see the changelog.