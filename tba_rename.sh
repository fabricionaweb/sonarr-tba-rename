#!/bin/bash -e

# -----------------------------------------
# Sonarr API key
API_KEY=""
# Sonarr API URL
API_URL="http://tower.lan:8989/api/v3"
# -----------------------------------------

# API param
HEADER="x-api-key: ${API_KEY}"
# CLI font colors
BLUE='\033[0;34m'
YELLOW='\033[0;33m'

# Find list of shows monitored
find_shows() {
  readarray -t monitoredSeries < <(curl --insecure -sSH "${HEADER}" "${API_URL}/series" | jq -c '.[] | select(.monitored == true) | {id,title}')

  if [[ ${#monitoredSeries[@]} -eq 0 ]]; then
    echo -e "${BLUE}No shows found with 'continuing' status."
    exit 0
  fi
}

# Look for episodes with TBA
search_episodes() {
  episodesToRename=()
  titles=$(jq -r '.title' <<<"${monitoredSeries[@]}")

  echo -e "${BLUE}Searching for TBA episodes in ${#monitoredSeries[@]} shows:"
  echo -e "${YELLOW}${titles}"

  for serie in "${monitoredSeries[@]}"; do
    seriesId="$(jq -r '.id' <<<"${serie}")"
    seriesTitle="$(jq -r '.title' <<<"${serie}")"

    # jq explained
    #   get only the values that passes on the regex: TBA|Episode [0-9]{1,}
    #   add the "seriesTitle" property to results (endpoint response doesnt have it)
    #   select necessary fields
    readarray -t episodesTBA < <(curl --insecure -sSH "${HEADER}" "${API_URL}/episodeFile?seriesId=${seriesId}" | jq --arg seriesTitle "${seriesTitle}" -c '.[] | select(.relativePath | test("TBA|Episode [0-9]{1,}")) | . += { seriesTitle: $seriesTitle } | {id,seriesId,seriesTitle,relativePath}')

    # if no TBA episodes found, go to the next serie
    [[ ${#episodesTBA[@]} -eq 0 ]] && continue

    episodesToRename+=("${episodesTBA[@]}")
    episodesPath="$(jq -r '.relativePath' <<<"${episodesTBA[@]}")"

    echo ""
    echo -e "${BLUE}Found TBA episodes in ${seriesTitle}:"
    echo -e "${YELLOW}${episodesPath}"
  done

  if [[ ${#episodesToRename[@]} -eq 0 ]]; then
    echo ""
    echo -e "${BLUE}No TBA episodes found."
    exit 0
  fi
}

# Call Sonarr refresh series command for the found series
refresh_series() {
  readarray -t seriesToRefresh < <(jq -sc 'group_by(.seriesId) | .[]' <<<"${episodesToRename[@]}")

  echo ""
  echo -e "${BLUE}Asking Sonarr to refresh metadata for:"

  for serie in "${seriesToRefresh[@]}"; do
    seriesId=$(jq -r '.[0].seriesId' <<<"${serie}")
    seriesTitle=$(jq -r '.[0].seriesTitle' <<<"${serie}")

    printf "${YELLOW}${seriesTitle}"
    curl --insecure -sSH "${HEADER}" -H 'content-type: application/json' -X POST "${API_URL}/command" -d "{\"name\":\"RefreshSeries\",\"seriesId\":${seriesId}}" -o /dev/null
    printf " ✓\\n"
  done
}

# Wait 30 seconds to Sonarr work, it should be enough
wait_working() {
  echo ""
  echo -e "${BLUE}Waiting 30 seconds to Sonarr work on it${YELLOW}"
  for i in {1..30}; do
    sleep 1
    printf "."
  done
  echo ""
}

# Call Sonnar rename files command
rename_episodes() {
  echo ""
  echo -e "${BLUE}Asking Sonarr to rename episodes for:"

  for serie in "${seriesToRefresh[@]}"; do
    seriesId=$(jq -r '.[0].seriesId' <<<"${serie}")
    seriesTitle=$(jq -r '.[0].seriesTitle' <<<"${serie}")
    episodesList=$(jq -r 'map(.id) | join(",")' <<<"${serie}")

    printf "${YELLOW}${seriesTitle}"
    curl --insecure -sSH "${HEADER}" -H 'content-type: application/json' -X POST "${API_URL}/command" -d "{\"name\":\"RenameFiles\",\"seriesId\":${seriesId},\"files\":[${episodesList}]}" -o /dev/null
    printf " ✓\\n"
  done
}

# Run the functions
find_shows
search_episodes
refresh_series
wait_working
rename_episodes
