#!/bin/bash

# Variables
USER="node_exporter"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/node_exporter.service"
PORT="9100"  # Port par défaut, peut être modifié
LISTEN_ADDRESS="::"  # Par défaut, écoute sur toutes les interfaces IPv4 et IPv6

# Fonction pour vérifier la dernière version disponible de Node Exporter
function get_latest_node_exporter_version() {
    echo "Checking the latest Node Exporter version..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    if [[ -z "$LATEST_VERSION" ]]; then
        echo "Failed to fetch the latest version. Using default version 1.8.1."
        LATEST_VERSION="v1.8.1"
    else
        echo "Latest version is $LATEST_VERSION."
    fi
}

# Fonction pour vérifier la version de Node Exporter installée
function check_installed_node_exporter_version() {
    if command -v node_exporter >/dev/null 2>&1; then
        INSTALLED_VERSION=$(node_exporter --version 2>&1 | grep -oP 'node_exporter, version \K[^\s]+')
        echo "Node Exporter version $INSTALLED_VERSION is already installed."
        if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
            echo "Node Exporter is already up to date."
            exit 0
        else
            echo "Updating Node Exporter from version $INSTALLED_VERSION to $LATEST_VERSION."
        fi
    else
        echo "Node Exporter is not installed. Proceeding with installation."
    fi
}

# Demander à l'utilisateur s'il veut un port personnalisé
read -p "Voulez-vous utiliser un port personnalisé pour Node Exporter (défaut: $PORT) ? [y/N]: " use_custom_port
if [[ "$use_custom_port" =~ ^[Yy]$ ]]; then
    read -p "Entrez le port souhaité: " custom_port
    if [[ "$custom_port" =~ ^[0-9]+$ ]]; then
        PORT="$custom_port"
    else
        echo "Le port est invalide. Utilisation du port par défaut $PORT."
    fi
fi

# Demander à l'utilisateur l'interface d'écoute (IPv4/IPv6 ou les deux)
read -p "Souhaitez-vous écouter sur toutes les interfaces IPv4 et IPv6 ? (Défaut: toutes les interfaces) [y/N]: " listen_all
if [[ "$listen_all" =~ ^[Nn]$ ]]; then
    read -p "Entrez l'adresse d'écoute (exemple: 0.0.0.0 pour IPv4, :: pour IPv6): " custom_address
    LISTEN_ADDRESS="$custom_address"
fi

# Si l'adresse d'écoute est IPv6, ajouter des crochets autour
if [[ "$LISTEN_ADDRESS" == "::" ]]; then
    LISTEN_ADDRESS="[::]"
fi

# Vérifier la dernière version disponible de Node Exporter
get_latest_node_exporter_version

# Vérifier la version actuelle de Node Exporter installée
check_installed_node_exporter_version

# Créer un utilisateur dédié pour Node Exporter
echo "Creating user for Node Exporter..."
if ! id -u "$USER" >/dev/null 2>&1; then
    useradd --no-create-home --shell /bin/false "$USER"
    echo "User '$USER' created."
else
    echo "User '$USER' already exists."
fi

# Télécharger et installer / mettre à jour Node Exporter
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/${LATEST_VERSION}/node_exporter-${LATEST_VERSION#v}.linux-amd64.tar.gz"
echo "Downloading Node Exporter from $DOWNLOAD_URL..."
curl -LO "$DOWNLOAD_URL"
tar -xzf "node_exporter-${LATEST_VERSION#v}.linux-amd64.tar.gz"
cp "node_exporter-${LATEST_VERSION#v}.linux-amd64/node_exporter" "$INSTALL_DIR/"

# Assigner les permissions appropriées
chown "$USER":"$USER" "$INSTALL_DIR/node_exporter"
chmod 755 "$INSTALL_DIR/node_exporter"

# Nettoyage des fichiers téléchargés
rm -rf "node_exporter-${LATEST_VERSION#v}.linux-amd64"*
echo "Node Exporter installed/updated."

# Créer le service systemd avec les paramètres personnalisés
echo "Creating systemd service..."
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=$USER
Group=$USER
Type=simple
ExecStart=$INSTALL_DIR/node_exporter --web.listen-address=${LISTEN_ADDRESS}:${PORT}

[Install]
WantedBy=default.target
EOF

# Recharger systemd pour prendre en compte le nouveau service
systemctl daemon-reload

# Redémarrer Node Exporter après la mise à jour
systemctl enable node_exporter
systemctl restart node_exporter

# Vérifier que le service fonctionne correctement
if systemctl is-active --quiet node_exporter; then
    echo "Node Exporter is running on $LISTEN_ADDRESS:$PORT."
else
    echo "There was an issue starting Node Exporter."
fi

exit 0
