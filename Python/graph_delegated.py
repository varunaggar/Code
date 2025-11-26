import pandas as pd

filename = '/Users/varunaggarwal/Documents/kagglehub/datasets/wcukierski/enron-email-dataset/versions/2/emails.csv'

try:
    # read_csv reads the entire file into a DataFrame
    df = pd.read_csv(filename)

    # Print the entire table
    print("--- DataFrame from CSV ---")
    print(df)
    print("\n" + "="*25 + "\n")

    # You can easily access columns
    print("--- Subjects ---")
    print(df['Subject'])
    print("\n" + "="*25 + "\n")

    # Iterate over rows
    print("--- Iterating over rows ---")
    for index, row in df.iterrows():
        print(f"Appointment: {row['Subject']}, Starts: {row['StartDate']} at {row['StartTime']}")

except FileNotFoundError:
    print(f"Error: The file '{filename}' was not found.")
