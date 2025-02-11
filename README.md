# OpenShift LDAP Playground

## Overview
This repository provides a **playground environment** for setting up an **LDAP server on OpenShift**, initializing it via **Ansible**, integrating it with **OAuth authentication**, and configuring a **CronJob** for periodic group imports. The goal is to create a **fully declarative and reproducible** setup that can be extended using GitOps principles.

## Features
- **Deploys an LDAP server** on OpenShift.
- **Initializes LDAP** using Ansible playbooks.
- **Integrates with OpenShift OAuth**, allowing LDAP-based authentication.
- **Configures a CronJob** to periodically import LDAP groups.
- **Uses Sealed Secrets** to store and encrypt sensitive data securely.
- **Fully declarative** for easy GitOps integration.

## ⚠️ Disclaimer
**This repository is for demo and testing purposes only.**

- The **LDAP setup and secrets** included here are for **playground use only**.
- **Sealed Secrets certificates are included** for reproducibility. If you need to use your own, you must generate new ones and update the Sealed Secrets controller accordingly.
- This is **not intended for production use**. Do not use these credentials or configurations in a real environment.

## Requirements
- OpenShift 4.x
- Ansible
- OpenShift CLI (`oc`)
- Kubeseal

## Setup Instructions
### 1. Clone the repository
```bash
git clone https://github.com/too-common-name/openshift-ldap-playground.git
cd openshift-ldap-playground
```

### 2. Execute setup script
```bash
./setup.sh <ocp-api-server> <admin-username> <admin-password>
```

## Customization
### Using Custom Certificates
If you want to use custom **Sealed Secrets certificates**, follow these steps:
1. Delete the existing Sealed Secrets controller.
2. Generate a new controller with custom certificates.
3. Re-encrypt secrets using the new certificates.
4. Apply the new Sealed Secrets to OpenShift.

### Using Helm or Kustomize
If you want a more modular approach, you can adapt the deployment using **Helm** or **Kustomize**.

## Future Improvements
- Add Helm chart support.
- Implement CI/CD automation for GitOps workflows.
- Enhance security by integrating a centralized secret management system (e.g., HashiCorp Vault).

## Contributing
Contributions are welcome! If you find issues or have suggestions for improvements, feel free to open a pull request or an issue.

## License
This project is licensed under the MIT License. See the LICENSE file for details.

