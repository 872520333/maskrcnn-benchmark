#!/bin/bash
export DNNL_PRIMITIVE_CACHE_CAPACITY=1024

ARGS=""

if [[ "$1" == "dnnl" ]]
then
    ARGS="$ARGS --dnnl"
    echo "### running auto_dnnl mode"
fi

if [[ "$2" == "int8" ]]
then
    ARGS="$ARGS --int8"
    echo "### running int8 datatype"
fi

if [[ "$3" == "jit" ]]
then
    ARGS="$ARGS --jit"
    echo "### running jit mode"
fi

if [[ "$4" == "calibration" ]]
then
   ARGS="$ARGS --calibration --iter-calib 20"
   echo "### running calibration"
fi

# ARGS="$ARGS --configure-dir $5"
# echo "### configure direction: $5"


CORES=`lscpu | grep Core | awk '{print $4}'`
SOCKETS=`lscpu | grep Socket | awk '{print $2}'`
TOTAL_CORES=`expr $CORES \* $SOCKETS`

# change this number to adjust number of instances
CORES_PER_INSTANCE=$CORES

KMP_SETTING="KMP_AFFINITY=granularity=fine,compact,1,0"

export OMP_NUM_THREADS=$CORES_PER_INSTANCE
export $KMP_SETTING

export TRAIN=0

echo -e "### using OMP_NUM_THREADS=$CORES_PER_INSTANCE"
echo -e "### using $KMP_SETTING\n\n"
sleep 3

INSTANCES=`expr $TOTAL_CORES / $CORES_PER_INSTANCE`
LAST_INSTANCE=`expr $INSTANCES - 1`
INSTANCES_PER_SOCKET=`expr $INSTANCES / $SOCKETS`
for i in $(seq 1 $LAST_INSTANCE); do
    numa_node_i=`expr $i / $INSTANCES_PER_SOCKET`
    start_core_i=`expr $i \* $CORES_PER_INSTANCE`
    end_core_i=`expr $start_core_i + $CORES_PER_INSTANCE - 1`
    LOG_i=inference_ipex_ins${i}.txt

    echo "### running on instance $i, numa node $numa_node_i, core list {$start_core_i, $end_core_i}..."
    numactl --physcpubind=$start_core_i-$end_core_i --membind=$numa_node_i python tools/test_net.py --config-file "configs/e2e_mask_rcnn_R_50_FPN_1x_coco2017_inf.yaml" \
        --ipex -i 200 $ARGS TEST.IMS_PER_BATCH 2 MODEL.DEVICE cpu 2>&1 | tee $LOG_i &
done

numa_node_0=0
start_core_0=0
end_core_0=`expr $CORES_PER_INSTANCE - 1`
LOG_0=inference_ipex_ins0.txt

echo "### running on instance 0, numa node $numa_node_0, core list {$start_core_0, $end_core_0}...\n\n"
numactl --physcpubind=$start_core_0-$end_core_0 --membind=$numa_node_0 python tools/test_net.py --config-file "configs/e2e_mask_rcnn_R_50_FPN_1x_coco2017_inf.yaml" \
    --ipex -i 200 $ARGS TEST.IMS_PER_BATCH 2 MODEL.DEVICE cpu 2>&1 | tee $LOG_0
