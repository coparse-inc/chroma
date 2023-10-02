CONTAINER_GROUP=$(az container list --query "[].name" -o tsv | grep macro-api-llm-embeddings-service-cg) #macro-api-llm-embeddings-service-cg-devdfcc219d
az acr login -n macroapillmdev

# Default value for clean_logs flag
clean_logs=false

# Loop through all the positional parameters
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --clean-logs)
        clean_logs=true
        echo "cleaning logs..."
        shift # remove the current parameter
        ;;
        *)
        # This would be executed for any other parameter not handled above.
        # If you don't expect any other parameters, you can simply ignore or print an error.
        echo "Unknown parameter: $1"
        shift
        ;;
    esac
done

# Recursive function to delete files and directories (this is currently specific to our setup for macro-api-llm-fs-dev)
delete_recursive() {
    local account_name="$1"
    local share_name="$2"
    local dir_path="$3"

    az storage file list --account-name "$account_name" --share-name "$share_name" --path "$dir_path" --query "[? !isDirectory].name" -o tsv | while read file; do
        if [ -z "$dir_path" ]; then
            az storage file delete --account-name "$account_name" --share-name "$share_name" --path "$file"
        else
            az storage file delete --account-name "$account_name" --share-name "$share_name" --path "${dir_path}/${file}"
        fi
    done

    # only 1 level deep because recursively deleting was not necessary
    az storage file list --account-name "$account_name" --share-name "$share_name" --path "$dir_path" --query "[?isDirectory].name" -o tsv | while read subdir; do
        az storage file list --account-name "$account_name" --share-name "$share_name" --path "$subdir" --query "[? !isDirectory].name" -o tsv | while read file; do
            az storage file delete --account-name "$account_name" --share-name "$share_name" --path "${subdir}/${file}"
        done

        az storage directory delete --account-name "$account_name" --share-name "$share_name" --name "${subdir}"
    done
}

if $clean_logs; then
    az container stop --name $CONTAINER_GROUP --resource-group macro-api-llm-rg-devcdbc79d7 # stop the container so we can delete the log
    mount | grep smbfs | awk '{print $3}' | xargs umount # unmount SMB connections from mac
    sleep 5 # sometimes storage file deletion doesn't work maybe this will help
    az storage file delete --account-name macroapillmfsdev --share-name macro-api-llm-embeddings-server-logs-dev --path chroma.log
    az storage file delete --account-name macroapillmfsdev --share-name macro-api-llm-embeddings-service-logs-dev --path log.log
    az storage file delete --account-name macroapillmfsdev --share-name macro-api-llm-embeddings-service-logs-dev --path uvicorn.log
    az storage file delete-batch --account-name macroapillmfsdev --source macro-api-llm-fs-dev
    delete_recursive "macroapillmfsdev" "macro-api-llm-fs-dev" ""
fi

docker build -t chromadb:latest --platform linux/amd64 .
docker tag chromadb:latest macroapillmdev.azurecr.io/chromadb:latest
docker push macroapillmdev.azurecr.io/chromadb:latest

cd ../macro-api/embeddings_server
docker build -t macro-api-embeddings_server:latest --platform linux/amd64 .
docker tag macro-api-embeddings_server:latest macroapillmdev.azurecr.io/embeddings-server:latest
docker push macroapillmdev.azurecr.io/embeddings-server:latest
cd ../../chroma

if $clean_logs; then
    az container start --name $CONTAINER_GROUP --resource-group macro-api-llm-rg-devcdbc79d7
    open smb://macroapillmfsdev:Sz9%2F%2FwMvmURFKbtpa%2BfDbz8o1rK7sABRLPLULlxgKlPOuYRYpcsuinytE1xoUgqXlRIQr1Vp2zah%2BAStxhT0rw%3D%3D@macroapillmfsdev.file.core.windows.net/macro-api-llm-embeddings-server-logs-dev
    open smb://macroapillmfsdev:Sz9%2F%2FwMvmURFKbtpa%2BfDbz8o1rK7sABRLPLULlxgKlPOuYRYpcsuinytE1xoUgqXlRIQr1Vp2zah%2BAStxhT0rw%3D%3D@macroapillmfsdev.file.core.windows.net/macro-api-llm-embeddings-service-logs-dev
    open smb://macroapillmfsdev:Sz9%2F%2FwMvmURFKbtpa%2BfDbz8o1rK7sABRLPLULlxgKlPOuYRYpcsuinytE1xoUgqXlRIQr1Vp2zah%2BAStxhT0rw%3D%3D@macroapillmfsdev.file.core.windows.net/macro-api-llm-fs-dev
else
    az container restart --name $CONTAINER_GROUP --resource-group macro-api-llm-rg-devcdbc79d7
fi