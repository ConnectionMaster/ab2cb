import csv
import sys

# Converting CSV to txt taking the first column.
with open(sys.argv[1], mode='r') as csv_file:
    csv_reader = csv.DictReader(csv_file)
    sourceString = ""
    for row in csv_reader:
        sourceString += row["text"]
        sourceString += "\n"
    with open('.intermediate/rules.txt', 'w') as source:
          source.write(sourceString)
