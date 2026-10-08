from pydantic import BaseModel, EmailStr, Field


class UserCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    password: str = Field(min_length=6)


class RegisterResponse(BaseModel):
    message: str
    id: int
    name: str
    email: EmailStr
