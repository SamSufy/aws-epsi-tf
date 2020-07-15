#!/bin/bash

apt-get update
apt-get install -y apache2
cat <<EOF > /var/www/html/index.html
<html>
<body>
<h1>Hello Timothee Maillard</h1>
<p>hostname is: $(hostname)</p>
<p>ami is: $(ami_name)</p>
</body>
</html>
EOF
systemctl restart apache2
systemctl enable apache2
