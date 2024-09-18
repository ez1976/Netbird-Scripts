#Clean Offline Machines
peer_list=$(mktemp)
user_list=$(mktemp)
netbird_api="XXXXXXXXX"
netbird_url="your.netbird.domain"
netbird_port=33073

	curl -X GET  -H 'Accept: application/json' -H "Authorization: Token $netbird_api" https://$netbird_url:$netbird_port/api/users | jq -r '.[] | "\(.name),\(.id)"' > $user_list
	curl -X GET  -H 'Accept: application/json' -H "Authorization: Token $netbird_api" https://$netbird_url:$netbird_port/api/peers | jq -r '.[] | select(.connected == false) | "\(.hostname),\(.id),\(.user_id)"' > $peer_list

	cat $peer_list  | grep -v relay | while read peer
	do
		user_id=$(echo $peer | cut -d ',' -f3)
		user_name=$(cat $user_list | grep $user_id | cut -d "," -f1)
		peer_id=$(echo $peer | cut -d ',' -f2)
		peer_name=$(echo $peer | cut -d ',' -f1)

		echo "removing offline machine: $peer_name (owner: $user_name)"
		curl -X DELETE  -H 'Accept: application/json' -H "Authorization: Token $netbird_api" https://$netbird_url:$netbird_port/api/peers/$peer_id

	done
done

