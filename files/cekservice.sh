#!/bin/bash
echo "[status]"; systemctl is-active docker 2>/dev/null; docker ps --format "{{.Names}} {{.Status}}" 2>/dev/null | head
