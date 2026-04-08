#!/bin/bash

# OpenClaw Sandbox Chaos Simulator

echo "=========================================="
echo " Starting OpenClaw Chaos Testing Suite..."
echo "=========================================="
echo ""

# Test 1: Assassinate the Node process (Gateway crash simulation)
echo "[Test 1] Simulating Overnight Gateway Crash..."
echo "-> Sending kill signal to internal Node process."
docker exec --user root openclaw-sandbox kill -9 1 >/dev/null 2>&1
echo "-> Node process killed! Docker should natively catch this and restart it."
echo "-> Waiting 10 seconds for automatic recovery..."
sleep 10

CONTAINER_STATE=$(docker inspect -f '{{.State.Status}}' openclaw-sandbox)
if [ "$CONTAINER_STATE" == "running" ]; then
    echo "✅ SUCCESS: Container successfully self-healed and is RUNNING."
else
    echo "❌ FAILED: Container did not recover. Status: $CONTAINER_STATE"
fi
echo ""

# Test 2: Nuke and Rebuild (Plugin dependency and boot test)
echo "[Test 2] Simulating Extreme Nuke & Rebuild (Plugin Preservation Test)..."
echo "-> Stopping and destroying current container instance..."
docker stop openclaw-sandbox >/dev/null
docker rm openclaw-sandbox >/dev/null
echo "-> Recreating container freshly from image..."
docker run -d --name openclaw-sandbox --restart always --user 1000:1000 --security-opt no-new-privileges:true -v ~/.openclaw:/home/node/.openclaw -e HOME=/home/node ghcr.io/openclaw/openclaw:latest >/dev/null
echo "-> Polling logs to verify plugins initialize cleanly..."
SUCCESS=0
for i in {1..20}; do
    docker logs --tail 200 openclaw-sandbox 2>&1 | grep -q "starting provider"
    if [ $? -eq 0 ]; then
        SUCCESS=1
        break
    fi
    sleep 5
done

if [ $SUCCESS -eq 1 ]; then
    echo "✅ SUCCESS: Container recreated flawlessly. Plugins automatically loaded natively!"
else
    echo "❌ FAILED: Telegram provider start log missing. May not have cleanly booted."
fi

echo ""
echo "=========================================="
echo " Chaos Testing Suite Complete!"
echo "=========================================="
echo ""
echo "🔥 ACTION REQUIRED: Open Telegram and text your bot right now. It should instantly reply!"
