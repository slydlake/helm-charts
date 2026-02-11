{{- define "wordpress.init-htaccess-setup" -}}
#!/bin/sh
# Script to setup .htaccess on persistent volume
# This runs in the base init container


echo "Starting .htaccess setup..."


# Copy and make injection script executable once
cp /scripts/htaccess-inject.sh /tmp/htaccess-inject.sh
chmod +x /tmp/htaccess-inject.sh


# Check if .htaccess already exists on persistent volume
if [ ! -f /tmp/wordpress/.htaccess ]; then
  echo ".htaccess not found on persistent volume, creating from ConfigMap..."


  # Copy .htaccess from ConfigMap and inject WordPress rules
  /tmp/htaccess-inject.sh \
    /configfiles/.htaccess \
    /tmp/wordpress/.htaccess \
    /scripts/wordpress-rewrite-rules.txt

  # Set correct ownership and permissions
  chown www-data:www-data /tmp/wordpress/.htaccess
  chmod 664 /tmp/wordpress/.htaccess
  echo "WordPress rewrite rules successfully injected and written to persistent volume!"
else
  echo ".htaccess already exists on persistent volume."


  # Extract WordPress block content from existing file (if it exists)
  if grep -q "# BEGIN WordPress" /tmp/wordpress/.htaccess; then
    echo "Extracting WordPress block content from existing .htaccess..."


    # Extract ONLY the content between markers (excluding the markers themselves)
    awk '/# BEGIN WordPress/,/# END WordPress/{if (!/# BEGIN WordPress/ && !/# END WordPress/) print}' /tmp/wordpress/.htaccess > /tmp/wp-block-content.txt


    # Start with fresh ConfigMap .htaccess and inject the existing WordPress block content
    /tmp/htaccess-inject.sh \
      /configfiles/.htaccess \
      /tmp/htaccess-new \
      /tmp/wp-block-content.txt


    # Replace old .htaccess with updated one
    mv /tmp/htaccess-new /tmp/wordpress/.htaccess
    chown www-data:www-data /tmp/wordpress/.htaccess
    chmod 664 /tmp/wordpress/.htaccess
    echo "ConfigMap .htaccess updated with existing WordPress block content!"
  else
    echo "No WordPress block found in existing .htaccess."


    # Inject default WordPress rules into fresh ConfigMap .htaccess
    /tmp/htaccess-inject.sh \
      /configfiles/.htaccess \
      /tmp/htaccess-new \
      /scripts/wordpress-rewrite-rules.txt

    # Replace old .htaccess with updated one
    mv /tmp/htaccess-new /tmp/wordpress/.htaccess
    chown www-data:www-data /tmp/wordpress/.htaccess
    chmod 664 /tmp/wordpress/.htaccess
    echo "ConfigMap .htaccess applied with default WordPress rules!"
  fi
fi


echo "========================================="
echo ".htaccess setup completed!"
echo "========================================="
{{- end -}}

{{- define "wordpress.init-htaccess-rewrite-rules" -}}
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
{{- end -}}

{{- define "wordpress.init-htaccess-inject" -}}
#!/bin/sh
# Script to inject WordPress rewrite rules into .htaccess
# Usage: htaccess-inject.sh <source-htaccess> <output-htaccess> <rules-file>


SOURCE_FILE="$1"
OUTPUT_FILE="$2"
RULES_FILE="$3"


awk -v rules_file="$RULES_FILE" '
BEGIN {
    in_wp=0
    wp_done=0
    # Read rules from file
    while ((getline line < rules_file) > 0) {
        rules = rules line "\n"
    }
    close(rules_file)
}
/# BEGIN WordPress/ {
    print
    printf "%s", rules
    in_wp=1
    wp_done=1
    next
}
/# END WordPress/ { in_wp=0 }
!in_wp || !wp_done { print }
' "$SOURCE_FILE" > "$OUTPUT_FILE"
{{- end -}}
