#!/bin/bash
echo "[DEBUG] Waiting for attach..." && sleep 2
sudo mkdir -p "$WORKDIR"

echo "[INFO] Adjusting permissions for Persistent Volume..."
# Aceasta este critică pentru K8s volumes
sudo chown -R $USER:$USER "$WORKDIR"
sudo chown -R $USER:$USER /home/$USER
sudo update-alternatives --set php /usr/bin/php8.3

# 1. Restore default configurations if volume is empty (Files)
if [ ! -f /home/$USER/.bashrc ]; then
    echo "[INFO] Restoring default .bashrc..."
    cp /etc/skel/.bashrc /home/$USER/.bashrc
    cp /etc/skel/.profile /home/$USER/.profile
    # Adaugam incarcarea NVM in .bashrc pentru shell-uri interactive non-login
    echo 'export NVM_DIR="/usr/local/share/nvm"' >> /home/$USER/.bashrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/$USER/.bashrc
    chown $USER:$USER /home/$USER/.bashrc /home/$USER/.profile
fi

# 2. Restore Apache Configuration to /home/coder/.apache2 if missing
if [ ! -d "/home/$USER/.apache2" ]; then
    echo "[INFO] Initializing Apache config in /home/$USER/.apache2..."
    cp -r /opt/apache2-backup /home/$USER/.apache2
    chown -R $USER:$USER /home/$USER/.apache2
fi

# 3. Link System Apache to Home Apache (Runtime Link)
# Doar daca nu este deja linkuit (verificare de siguranta)
if [ ! -L "/etc/apache2" ]; then
    echo "[INFO] Linking /etc/apache2 to /home/$USER/.apache2..."
    sudo rm -rf /etc/apache2
    sudo ln -s /home/$USER/.apache2 /etc/apache2
fi

# 4. Create necessary directories
mkdir -p /home/$USER/logs
mkdir -p /home/$USER/www

# 5. SSL Certificate Generation (Self-Signed)
SSL_DIR="/home/$USER/.apache2/ssl"
mkdir -p "$SSL_DIR"
if [ ! -f "$SSL_DIR/server.crt" ]; then
    echo "[INFO] Generating self-signed SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/server.key" \
        -out "$SSL_DIR/server.crt" \
        -subj "/C=RO/ST=Bucharest/L=Bucharest/O=Development/OU=Coder/CN=localhost"
    chown -R $USER:$USER "$SSL_DIR"
fi

# Ensure Apache SSL config points to our certs
# We assume default-ssl.conf exists or we patch default config
# A safe bet is to create a dedicated snippet if not present
if [ ! -f "/etc/apache2/conf-available/coder-ssl.conf" ]; then
    echo "[INFO] Configuring Apache SSL paths..."
    echo "SSLCertificateFile $SSL_DIR/server.crt" | sudo tee /etc/apache2/conf-available/coder-ssl.conf
    echo "SSLCertificateKeyFile $SSL_DIR/server.key" | sudo tee -a /etc/apache2/conf-available/coder-ssl.conf
    sudo a2enconf coder-ssl
fi

# Enable SSL module and default SSL site
sudo a2enmod ssl
sudo a2ensite default-ssl

# Laravel setup / Env setup (placeholder)

# Start code-server (binarul este deja instalat in imagine)
echo "[INFO] Starting code-server..."
code-server --auth none --port 13337 --disable-telemetry > /tmp/code-server.log 2>&1 &

# Restart Apache pentru a prelua noile configurari/user
sudo service apache2 stop
sudo sed -i 's/^APACHE_RUN_USER=.*/APACHE_RUN_USER=coder/' /etc/apache2/envvars
sudo sed -i 's/^APACHE_RUN_GROUP=.*/APACHE_RUN_GROUP=coder/' /etc/apache2/envvars
sudo a2enmod rewrite headers
sudo service apache2 start

# Dacă vrei neapărat Opencode agent la latest, decomentează linia de mai jos,
# dar pentru viteză maximă ar trebui să fie în Dockerfile.
# curl -fsSL https://opencode.ai/install | bash
