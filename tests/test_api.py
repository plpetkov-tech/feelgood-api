"""API tests"""
import pytest
from fastapi.testclient import TestClient
from src.app import app


@pytest.fixture
def client():
    """Test client fixture"""
    with TestClient(app) as client:
        yield client


def test_root(client):
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    assert "message" in response.json()


def test_health(client):
    """Test health endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "build_info" in data


def test_get_phrase(client):
    """Test phrase generation"""
    response = client.get("/phrase")
    assert response.status_code == 200
    data = response.json()
    assert "phrase" in data
    assert "category" in data
    assert "timestamp" in data


def test_get_phrase_with_category(client):
    """Test phrase generation with specific category"""
    response = client.get("/phrase?category=motivation")
    assert response.status_code == 200
    data = response.json()
    assert data["category"] == "motivation"


def test_get_phrase_invalid_category(client):
    """Test phrase generation with invalid category"""
    response = client.get("/phrase?category=invalid")
    assert response.status_code == 400


def test_security_headers(client):
    """Test security headers are present"""
    response = client.get("/")
    assert "X-Content-Type-Options" in response.headers
    assert "X-Frame-Options" in response.headers
    assert "X-SBOM-Location" in response.headers
