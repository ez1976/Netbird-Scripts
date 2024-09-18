netbird_route=10.16.8.0/21 # example
netbird_api="XXXXXXXXX"
netbird_url="your.netbird.domain"
netbird_port=33073
peer_group="xxxxxxxx"

matched_object=$(jq --arg network "$netbird_route" '.[] | select(.network == $network)' "$route_full")
if [[ -n "$matched_object" ]]; then
    # Load JSON data into variables using jq
	matched_object=$(jq --arg network "$netbird_route" '.[] | select(.network == $network)' "$route_full")
    # Load JSON data into variables using jq
    description=$(echo "$matched_object" | jq -r '.description')
    groups=$(echo "$matched_object" | jq -r '.groups | map("\"" + . + "\"") | join(", ")')
    id=$(echo "$matched_object" | jq -r '.id')
    peer_groups=$(echo "$matched_object" | jq -r '.peer_groups[]')
    network=$(echo "$matched_object" | jq -r '.network')
    network_id=$(echo "$matched_object" | jq -r '.network_id')

    # Output the values of the variables
	echo "network_id: $network_id"
    echo "description: $description"
    echo "groups: $groups"
    echo "id: $id"
    echo "peer_groups: $peer_groups"
    echo "network: $network"

    echo "Updating Route: $network_id (id:$id) on Netbird"

	curl -X PUT https://$netbird_url:$netbird_port/api/routes/$id \
	-H 'Accept: application/json' \
	-H 'Content-Type: application/json' \
	-H "Authorization: Token $netbird_api" \
	--data "{\"description\": \"$description\", \"network_id\": \"$network_id\", \"enabled\": true,  \"peer_groups\": [ \"$peer_group\" ], \"network\": \"$network\", \"metric\": 9999, \"masquerade\": true, \"groups\": [ $groups ]}"

else
    echo "Network ID '$network_id' not found in the JSON file."
fi
