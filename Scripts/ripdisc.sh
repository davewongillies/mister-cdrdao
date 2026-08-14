#!/usr/bin/env bash
set -eo pipefail
RIPDISC_PATH=/media/fat/Scripts/.config/mister-cdrdao

# Paths to check for games directory
MEDIA_PATHS=(
  '/media/usb0'
  '/media/usb1'
  '/media/usb2'
  '/media/usb3'
  '/media/usb4'
  '/media/usb5'
  '/media/fat/cifs'
  '/media/fat'
)

for media_path in "${MEDIA_PATHS[@]}"; do
  if [ -e "${media_path}/games" ]; then
    GAMES_PATH="${media_path}"
    break
  fi
done

TMP_PATH=$(mktemp -d --tmpdir="${GAMES_PATH}")

cd "${TMP_PATH}"

# Do this to wait for the drive to be ready
# Try to get a disc label
echo Reading disc label...
DISCNAME=$(lsblk -n -o LABEL /dev/sr0 | sed 's/(.*)/$1/')
if [ -z "$DISCNAME" ]; then
    DISCNAME=unknown
fi

# Dump the disc and convert the toc to cue
rip_disc() {
  echo "Ripping disc with label $DISCNAME..."
  ${RIPDISC_PATH}/cdrdao read-cd --read-raw --datafile "${DISCNAME}.bin" --device /dev/sr0 --driver generic-mmc-raw "${DISCNAME}.toc"
  echo "Converting ${DISCNAME}.toc to ${DISCNAME}.cue..."
  ${RIPDISC_PATH}/toc2cue -v 0 "${DISCNAME}.toc" "${DISCNAME}.cue"
}

process() {
  # if the CUE contains multiple tracks
  if [ "$(grep -c TRACK "${DISCNAME}.cue")" -gt 1 ]; then
      # Split the BIN file
      echo "Multiple tracks detected. Splitting BIN/CUE. This may take a long time if there are many audio tracks..."
      "${RIPDISC_PATH}/binmerge" -s "${DISCNAME}".cue "${DISCNAME}" -o ./output
      rm "${DISCNAME}.bin" "${DISCNAME}.cue"
      mv ./output/* .
      # check if CUE contains audio tracks
      if [ "$(grep -c AUDIO "${DISCNAME}.cue")" -gt 0 ]; then
          AUDIOFLAG=
      else
          AUDIOFLAG=--no-audio
      fi
  else
      AUDIOFLAG=--no-audio
  fi

  echo "Identifying platform and game..."
  PLATFORM=$(python3 ${RIPDISC_PATH}/processcue.py "${DISCNAME}.cue" $AUDIOFLAG | tee /dev/stderr | grep -i Platform | awk -F= '{print $2}')
  # Default to PSX if the platform was not determined
  if [ -z "$PLATFORM" ]; then
      PLATFORM=PSX
  fi
}

cleanup() {
  rm -f "${DISCNAME}.toc" "${DISCNAME}.cue"
  echo "Moving to $PLATFORM directory..."
  cp -f ./*.cue ./*.bin "${GAMES_PATH}/games/${PLATFORM}"
  rm -f ./*.cue ./*.bin

  cd /media/fat/Scripts

  # Cleanup temporary directory
  rm -rf "${TMP_PATH}"

  echo "Complete!"
  eject
}

rip_disc
process
cleanup
