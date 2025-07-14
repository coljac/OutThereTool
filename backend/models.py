from sqlalchemy import Column, Integer, String, Numeric, DateTime, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime

Base = declarative_base()

class Galaxy(Base):
    __tablename__ = "galaxy"
    
    id = Column(String, primary_key=True)
    status = Column(Integer, nullable=False)
    redshift = Column(Numeric)
    filters = Column(Integer, default=1)
    field = Column(String(255))
    
    comments = relationship("GalaxyComment", back_populates="galaxy", cascade="all, delete-orphan")

class GalaxyComment(Base):
    __tablename__ = "galaxy_comment"
    
    galaxy_id = Column(String, ForeignKey("galaxy.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(String, primary_key=True)
    status = Column(Integer, nullable=False)
    redshift = Column(Numeric)
    comment = Column(String)
    updated = Column(DateTime, nullable=False, default=datetime.utcnow)
    
    galaxy = relationship("Galaxy", back_populates="comments")