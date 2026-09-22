#!/bin/bash
#change vm names
echo "Shutting down control-plane..."
virsh shutdown cp #take longer time

echo "Shutting down work-1..."
virsh shutdown work-1

echo "Shutting down work-2..."
virsh shutdown work-2


#chmod +x ./fille.sh
#./file.sh