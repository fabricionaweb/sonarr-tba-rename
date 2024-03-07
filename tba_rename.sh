#!/bin/bash -e

# -----------------------------------------
# Sonarr API key
API_KEY=""
# Sonarr API URL
API_URL="http://tower.lan:8989/api/v3"
# -----------------------------------------

# API param
HEADER="x-api-key: ${API_KEY}"
# Filter episodes by released date (in days), accepts env var, eg: `FILTER_DAYS=30 ./tba-rename.sh`
FILTER_DAYS="${FILTER_DAYS:-14}"

# Find list of shows monitored
find_shows() {
  readarray -t monitoredSeries < <(curl -sSH "${HEADER}" "${API_URL}/series" |
    jq -c '.[] | select(.monitored == true) | {id,title}')

  if [[ ${#monitoredSeries[@]} -eq 0 ]]; then
    echo -e "=> No monitored shows available."
    exit 0
  fi
}

# Look for episodes with TBA
search_episodes() {
  episodesToRename=()
  titles=$(jq -r '.title' <<<"${monitoredSeries[@]}")
  limitDate=$(date -d "-${FILTER_DAYS} days" +%s)

  echo -e "=> Searching for TBA episodes within ${FILTER_DAYS} days in ${#monitoredSeries[@]} shows:"
  echo -e "${titles}"

  for serie in "${monitoredSeries[@]}"; do
    seriesId="$(jq -r '.id' <<<"${serie}")"
    seriesTitle="$(jq -r '.title' <<<"${serie}")"

    # airDateUtc value comes from a separated endpoint
    # build a list of ids to filter on the next query
    episodesFiltered="$(curl -sSH "${HEADER}" "${API_URL}/episode?seriesId=${seriesId}" |
      jq --argjson limitDate "${limitDate}" \
        -c '[.[] | select((.hasFile == true) and (.airDateUtc? | fromdateiso8601) > $limitDate) | .episodeFileId]')"

    # no episode on date range, go to the next serie
    [[ "${episodesFiltered}" == "[]" ]] && continue

    # jq explained
    #   filter values that belongs to the date range
    #   filter values that passes on the regex: TBA|Episode [0-9]{1,}
    #   add the "seriesTitle" property to results (endpoint response doesnt have it)
    #   return necessary fields
    readarray -t episodesTBA < <(curl -sSH "${HEADER}" "${API_URL}/episodeFile?seriesId=${seriesId}" |
      jq --arg seriesTitle "${seriesTitle}" --argjson episodesFiltered "${episodesFiltered}" \
        -c '.[] | select(($episodesFiltered[] == .id) and (.relativePath | test("TBA|Episode [0-9]{1,}"))) | . += { seriesTitle: $seriesTitle } | {id,seriesId,seriesTitle,relativePath}')

    # if no TBA episodes found, go to the next serie
    [[ ${#episodesTBA[@]} -eq 0 ]] && continue

    episodesToRename+=("${episodesTBA[@]}")
    episodesPath="$(jq -r '.relativePath' <<<"${episodesTBA[@]}")"

    echo -e "\\n=> Found TBA episodes in ${seriesTitle}:"
    echo -e "${episodesPath}"
  done

  if [[ ${#episodesToRename[@]} -eq 0 ]]; then
    echo -e "\\n=> No TBA episodes found."
    exit 0
  fi
}

# Call Sonarr refresh series command for the found series
refresh_series() {
  readarray -t seriesToRefresh < <(jq -sc 'group_by(.seriesId) | .[]' <<<"${episodesToRename[@]}")

  echo -e "\\n=> Asking Sonarr to refresh metadata for:"

  for serie in "${seriesToRefresh[@]}"; do
    seriesId=$(jq -r '.[0].seriesId' <<<"${serie}")
    seriesTitle=$(jq -r '.[0].seriesTitle' <<<"${serie}")

    printf "${seriesTitle}"
    curl -sSH "${HEADER}" -X POST "${API_URL}/command" \
      -H 'content-type: application/json' -d "{\"name\":\"RefreshSeries\",\"seriesId\":${seriesId}}" \
      -o /dev/null
    printf " ✓\\n"
  done
}

# Wait 30 seconds to Sonarr work, it should be enough
wait_working() {
  echo -e "\\n=> Waiting 30 seconds to Sonarr work on it:"
  for i in {1..30}; do
    sleep 1
    printf "."
  done
  echo -e ""
}

# Call Sonarr rename files command
rename_episodes() {
  echo -e "\\n=> Asking Sonarr to rename episodes for: "

  for serie in "${seriesToRefresh[@]}"; do
    seriesId=$(jq -r '.[0].seriesId' <<<"${serie}")
    seriesTitle=$(jq -r '.[0].seriesTitle' <<<"${serie}")
    episodesList=$(jq -r 'map(.id|tostring) | join(",")' <<<"${serie}")

    printf "${seriesTitle}"
    curl -sSH "${HEADER}" -X POST "${API_URL}/command" \
      -H 'content-type: application/json' -d "{\"name\":\"RenameFiles\",\"seriesId\":${seriesId},\"files\":[${episodesList}]}" \
      -o /dev/null
    printf " ✓\\n"
  done
}

# Run the functions
find_shows
search_episodes
refresh_series
wait_working
rename_episodes
