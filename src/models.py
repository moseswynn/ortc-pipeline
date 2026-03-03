from datetime import datetime

from pydantic import BaseModel


class Record(BaseModel):
    id: int
    name: str
    email: str
    age: int
    salary: float
    department: str
    is_active: bool
    score: float
    notes: str
    created_at: datetime

    def serialize(self) -> str:
        return self.model_dump_json()

    @classmethod
    def deserialize(cls, data: str) -> "Record":
        return cls.model_validate_json(data)


class BatchResponse(BaseModel):
    records: list[Record]
    total: int
    offset: int
    limit: int
