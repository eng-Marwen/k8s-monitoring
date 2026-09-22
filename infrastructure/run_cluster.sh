#!/bin/bash
#chanege vm  ip@
CONTROL_PLANE="cp"
WORKER_1="work-1"
WORKER_2="work-2"
CONTROL_PLANE_IP="192.168.71.104"

cd "$(dirname "$0")"
echo "=== Applying Terraform configuration ==="
terraform apply -auto-approve

echo ""
echo "=== Starting Kubernetes VMs ==="

for VM in "$CONTROL_PLANE" "$WORKER_1" "$WORKER_2"; do
    if virsh domstate "$VM" | grep -q "running"; then
        echo "$VM is already running."
    else
        echo "Starting $VM..."
        virsh start "$VM"
    fi
done

echo ""
echo "=== Waiting for control plane SSH ==="

until ssh \
    -o ConnectTimeout=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    ubuntu@"$CONTROL_PLANE_IP" "exit" 2>/dev/null
do
    echo "Control plane is not ready yet... retrying in 2 seconds."
    sleep 2
done

echo "SSH connection successful."

echo ""
echo "=== Waiting for kubeconfig on control plane ==="

until ssh \
    -o ConnectTimeout=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    ubuntu@"$CONTROL_PLANE_IP" "test -f /home/ubuntu/.kube/config" 2>/dev/null
do
    echo "kubeconfig not ready yet (kubeadm init still running)... retrying in 5 seconds."
    sleep 5
done

echo ""
echo "=== Copying Kubernetes configuration ==="

mkdir -p ~/.kube

scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    ubuntu@"$CONTROL_PLANE_IP":/home/ubuntu/.kube/config \
    ~/.kube/config

chmod 600 ~/.kube/config

echo ""
echo "=== Waiting for Kubernetes API ==="

until kubectl get nodes >/dev/null 2>&1
do
    echo "Kubernetes API is not ready yet... retrying in 3 seconds."
    sleep 3
done

echo ""
echo "=== Kubernetes cluster is ready ==="
echo ""

kubectl get nodes