from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.user import RegisterResponse, UserCreate
from app.services.user_service import EmailAlreadyRegisteredError, register_user

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=RegisterResponse, status_code=status.HTTP_201_CREATED)
def register(payload: UserCreate, db: Session = Depends(get_db)):
    """Step 1: register a new user."""
    try:
        user = register_user(db, payload)
    except EmailAlreadyRegisteredError:
        raise HTTPException(status_code=400, detail="Email is already registered")
    return RegisterResponse(message="Registered successfully", id=user.id, name=user.name, email=user.email)
