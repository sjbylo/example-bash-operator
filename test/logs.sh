while true; do kubectl logs $(kubectl get po --no-headers --field-selector status.phase=Running| grep bash-op | awk '{print $1}') -f 2>/dev/null; sleep 1; echo; done
