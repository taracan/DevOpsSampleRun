from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.models.user import User
from app.schemas.user import UserCreate


class EmailAlreadyRegisteredError(Exception):
    pass


def register_user(db: Session, data: UserCreate) -> User:
    if db.scalar(select(User).where(User.email == data.email)):
        raise EmailAlreadyRegisteredError

    user = User(name=data.name, email=data.email, password_hash=hash_password(data.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
