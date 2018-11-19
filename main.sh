# Converting the csv to a ab2cb readable txt format.
python csvToTxt.py $1

# executing ab2cb
. bin/activate.sh
make dev
ab2cb -o $2 .intermediate/rules.txt

# Deactivating ab2cb
. bin/deactivate.sh
