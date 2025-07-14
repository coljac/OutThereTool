#!/usr/bin/env python3
"""
Script to import galaxy data from gal_data.csv into PostgreSQL database
"""

import csv
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from models import Galaxy, Base

def import_galaxy_data(csv_file: str, database_url: str):
    """Import galaxy data from CSV file into PostgreSQL"""
    
    # Create database connection
    engine = create_engine(database_url)
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    
    session = SessionLocal()
    
    try:
        with open(csv_file, 'r') as file:
            csv_reader = csv.DictReader(file)
            
            galaxies_added = 0
            galaxies_updated = 0
            
            for row in csv_reader:
                galaxy_id = row['object_id']
                field = row['field']
                redshift = float(row['redshift']) if row['redshift'] != '0.000000' else None
                filters = int(row['num_filters'])
                
                # Check if galaxy already exists
                existing_galaxy = session.query(Galaxy).filter(Galaxy.id == galaxy_id).first()
                
                if existing_galaxy:
                    # Update existing galaxy
                    existing_galaxy.field = field
                    existing_galaxy.redshift = redshift
                    existing_galaxy.filters = filters
                    galaxies_updated += 1
                else:
                    # Create new galaxy with default status
                    new_galaxy = Galaxy(
                        id=galaxy_id,
                        status=0,  # Default status
                        redshift=redshift,
                        filters=filters,
                        field=field
                    )
                    session.add(new_galaxy)
                    galaxies_added += 1
                
                # Commit every 100 records for better performance
                if (galaxies_added + galaxies_updated) % 100 == 0:
                    session.commit()
                    print(f"Processed {galaxies_added + galaxies_updated} records...")
            
            # Final commit
            session.commit()
            
            print(f"Import completed!")
            print(f"Galaxies added: {galaxies_added}")
            print(f"Galaxies updated: {galaxies_updated}")
            print(f"Total processed: {galaxies_added + galaxies_updated}")
            
    except Exception as e:
        session.rollback()
        print(f"Error importing data: {e}")
        raise
    finally:
        session.close()

if __name__ == "__main__":
    # Get database URL from environment or use default
    database_url = os.getenv("DATABASE_URL", "postgresql://user:password@localhost/outtheretool")
    csv_file = "gal_data.csv"
    
    if not os.path.exists(csv_file):
        print(f"Error: {csv_file} not found")
        exit(1)
    
    print(f"Importing data from {csv_file} to {database_url}")
    import_galaxy_data(csv_file, database_url)