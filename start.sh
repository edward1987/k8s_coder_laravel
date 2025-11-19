#!/bin/bash
echo "[DEBUG] Waiting for attach..." && sleep 2
sudo mkdir -p "$WORKDIR"

echo "[INFO] Adjusting permissions for Persistent Volume..."
# Aceasta este critică pentru K8s volumes
sudo chown -R $USER:$USER "$WORKDIR"
sudo chown -R $USER:$USER /home/$USER
sudo update-alternatives --set php /usr/bin/php8.3

# Restore default configurations if volume is empty
if [ ! -f /home/$USER/.bashrc ]; then
    echo "[INFO] Restoring default .bashrc..."
    cp /etc/skel/.bashrc /home/$USER/.bashrc
    cp /etc/skel/.profile /home/$USER/.profile
    # Adaugam incarcarea NVM in .bashrc pentru shell-uri interactive non-login
    echo 'export NVM_DIR="/usr/local/share/nvm"' >> /home/$USER/.bashrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/$USER/.bashrc
    chown $USER:$USER /home/$USER/.bashrc /home/$USER/.profile
fi

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
