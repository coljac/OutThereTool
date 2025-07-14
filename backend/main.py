from fastapi import FastAPI, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime

from database import get_db, create_tables
from models import Galaxy, GalaxyComment
from schemas import GalaxyCommentCreate, GalaxyCommentResponse, GalaxyResponse
from auth import get_current_user

app = FastAPI(title="OutThereTool Backend API", version="1.0.0")

@app.on_event("startup")
def startup_event():
    create_tables()

@app.get("/")
def read_root():
    return {"message": "OutThereTool Backend API"}

@app.post("/galaxies/{galaxy_id}/comments", response_model=GalaxyCommentResponse)
def create_galaxy_comment(
    galaxy_id: str,
    comment_data: GalaxyCommentCreate,
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Add or update a galaxy comment for the current user"""
    
    # Check if galaxy exists
    galaxy = db.query(Galaxy).filter(Galaxy.id == galaxy_id).first()
    if not galaxy:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Galaxy not found"
        )
    
    # Check if comment already exists for this user/galaxy pair
    existing_comment = db.query(GalaxyComment).filter(
        GalaxyComment.galaxy_id == galaxy_id,
        GalaxyComment.user_id == current_user
    ).first()
    
    if existing_comment:
        # Update existing comment
        existing_comment.status = comment_data.status
        existing_comment.redshift = comment_data.redshift
        existing_comment.comment = comment_data.comment
        existing_comment.updated = datetime.utcnow()
        db.commit()
        db.refresh(existing_comment)
        return existing_comment
    else:
        # Create new comment
        new_comment = GalaxyComment(
            galaxy_id=galaxy_id,
            user_id=current_user,
            status=comment_data.status,
            redshift=comment_data.redshift,
            comment=comment_data.comment,
            updated=datetime.utcnow()
        )
        db.add(new_comment)
        db.commit()
        db.refresh(new_comment)
        return new_comment

@app.get("/galaxies/{galaxy_id}", response_model=GalaxyResponse)
def get_galaxy_with_comments(
    galaxy_id: str,
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Fetch a single galaxy's info along with all comments"""
    
    galaxy = db.query(Galaxy).filter(Galaxy.id == galaxy_id).first()
    if not galaxy:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Galaxy not found"
        )
    
    return galaxy

@app.get("/galaxies/{galaxy_id}/comments", response_model=List[GalaxyCommentResponse])
def get_galaxy_comments(
    galaxy_id: str,
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get all comments for a specific galaxy"""
    
    # Check if galaxy exists
    galaxy = db.query(Galaxy).filter(Galaxy.id == galaxy_id).first()
    if not galaxy:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Galaxy not found"
        )
    
    comments = db.query(GalaxyComment).filter(
        GalaxyComment.galaxy_id == galaxy_id
    ).all()
    
    return comments

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)