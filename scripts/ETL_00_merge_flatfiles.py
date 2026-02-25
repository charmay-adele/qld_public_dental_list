# # # # # Step 1
# We cannot parse xlsx files directly in postgreSQL.
# We need to convert them to csv files first.
# This script converts all xlsx files in a given directory to csv files in another directory.


#loop through all xlsx files in the input directory  
# and convert them to csv files in the output directory

from pathlib import Path       # Import Path class for handling file and folder paths in a cross-platform way
import pandas as pd            # Import pandas for reading Excel files and writing CSV files
import logging                 # Import logging module to log messages to the console

# Set up logging: specify level and format for messages
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)  # Create a logger object to use for logging messages

# Define folder paths
input_dir = r"F:\Git\projects\waiting_list\data\raw\xlsx"  # Folder where Excel (.xlsx) files are located
output_dir = r"F:\Git\projects\waiting_list\data\raw\csv"  # Folder where CSV files will be saved

# Define function to convert all Excel files in input_dir to CSV files in output_dir
def convert_xlsx_to_csv(input_dir, output_dir):
    input_path = Path(input_dir)        # Convert input_dir string to a Path object for easier file handling
    output_path = Path(output_dir)      # Convert output_dir string to a Path object
    output_path.mkdir(parents=True, exist_ok=True)  # Create the output folder if it doesn’t exist

    # Loop through every Excel file (.xlsx) in the input directory
    for xlsx_file in input_path.glob("*.xlsx"):
        logger.info(f"Processing {xlsx_file.name}")  # Log which file is currently being processed
        
        try:
            df = pd.read_excel(xlsx_file, sheet_name="Data")          # Read the Excel file into a pandas DataFrame
            csv_file = output_path / f"{xlsx_file.stem}.csv"  # Create path for CSV file using same name as Excel file
            df.to_csv(csv_file, index=False, encoding='utf-8-sig')  # Save DataFrame as CSV without row indices, UTF-8 for Excel
            logger.info(f"Successfully converted {xlsx_file.name} 'Data'to {csv_file.name}")  # Log success message
        
        except Exception as e:
            logger.error(f"Error processing {xlsx_file.name}: {e}")  # Log any errors encountered during processing

# Call the function to run the conversion process
convert_xlsx_to_csv(input_dir, output_dir)




# # # # # Step 2 join all csv files into a single master dataframe
# Folder with your CSVs
data_path = Path("F:/Git/projects/waiting_list/data/raw/csv") #Folder with csv files

# Read and combine
df = pd.concat([pd.read_csv(f) for f in data_path.glob("*.csv")], ignore_index=True)

# Save combined dataframe to a new CSV
df.to_csv("F:/Git/projects/waiting_list/data/processed/master_dataset.csv", index=False)

