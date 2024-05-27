#!/bin/bash

message="WARNING: The selected launch configuration will deploy to a productive environment.\n\nDo you want to proceed? [y/N]"
echo -e $message

read -r -p "" response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  echo "Launch cancelled by user."
  exit 1
fi