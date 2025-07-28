from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from decimal import Decimal

class GalaxyCommentCreate(BaseModel):
    status: int
    redshift: Optional[Decimal] = None
    comment: Optional[str] = None
    galaxy_class: Optional[int] = 0
    checkboxes: Optional[int] = 0

class GalaxyCommentResponse(BaseModel):
    galaxy_id: str
    user_id: str
    status: int
    redshift: Optional[Decimal] = None
    comment: Optional[str] = None
    galaxy_class: Optional[int] = 0
    checkboxes: Optional[int] = 0
    updated: datetime
    
    class Config:
        from_attributes = True

class GalaxyResponse(BaseModel):
    id: str
    status: int
    redshift: Optional[Decimal] = None
    filters: Optional[int] = None
    field: Optional[str] = None
    comments: List[GalaxyCommentResponse] = []
    
    class Config:
        from_attributes = True