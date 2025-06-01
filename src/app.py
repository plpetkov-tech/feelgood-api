"""Feel Good Phrases API - Main Application"""
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Dict, List

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from .phrases import PhraseGenerator


class HealthResponse(BaseModel):
    status: str
    timestamp: datetime
    version: str
    build_info: Dict[str, str]


class PhraseResponse(BaseModel):
    phrase: str
    category: str
    timestamp: datetime


class SecurityHeaders(BaseModel):
    sbom_location: str
    vex_location: str
    provenance_location: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    # Startup
    app.state.phrase_generator = PhraseGenerator()
    print("Feel Good API started with supply chain security features")
    yield
    # Shutdown
    print("Feel Good API shutting down")


app = FastAPI(
    title="Feel Good Phrases API",
    description="An API that serves motivational phrases with comprehensive supply chain security",
    version="1.0.0",
    lifespan=lifespan
)

# Security headers middleware
@app.middleware("http")
async def add_security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["X-SBOM-Location"] = "/security/sbom"
    response.headers["X-VEX-Location"] = "/security/vex"
    response.headers["X-Provenance-Location"] = "/security/provenance"
    return response

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", response_model=Dict[str, str])
async def root():
    """Root endpoint with API information"""
    return {
        "message": "Welcome to the Feel Good Phrases API",
        "docs": "/docs",
        "health": "/health",
        "security": "/security"
    }


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint with build information"""
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(),
        version="1.0.0",
        build_info={
            "python_version": "3.11",
            "build_date": datetime.now().isoformat(),
            "sbom_generated": "true",
            "slsa_level": "3"
        }
    )


@app.get("/phrase", response_model=PhraseResponse)
async def get_phrase(category: str = None):
    """Get a random feel-good phrase"""
    try:
        phrase, used_category = app.state.phrase_generator.get_phrase(category)
        return PhraseResponse(
            phrase=phrase,
            category=used_category,
            timestamp=datetime.now()
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/phrases/categories", response_model=List[str])
async def get_categories():
    """Get all available phrase categories"""
    return app.state.phrase_generator.get_categories()


@app.get("/security", response_model=SecurityHeaders)
async def security_info():
    """Get security and supply chain information"""
    return SecurityHeaders(
        sbom_location="/security/sbom",
        vex_location="/security/vex",
        provenance_location="/security/provenance"
    )


@app.get("/security/sbom")
async def get_sbom():
    """Get the Software Bill of Materials"""
    try:
        with open("/app/sbom.json", "r") as f:
            import json
            return JSONResponse(content=json.load(f))
    except FileNotFoundError:
        return JSONResponse(
            status_code=404,
            content={"error": "SBOM not found. Generated during build process."}
        )


@app.get("/security/vex")
async def get_vex():
    """Get the Vulnerability Exploitability eXchange document"""
    try:
        with open("/app/vex.json", "r") as f:
            import json
            return JSONResponse(content=json.load(f))
    except FileNotFoundError:
        return JSONResponse(
            status_code=404,
            content={"error": "VEX document not found."}
        )


@app.get("/security/provenance")
async def get_provenance():
    """Get SLSA provenance information"""
    return {
        "builder": "github-actions",
        "buildType": "https://github.com/slsa-framework/slsa-github-generator",
        "invocation": {
            "configSource": {
                "uri": "https://github.com/yourusername/feelgood-api",
                "digest": {"sha1": "placeholder"},
                "entryPoint": ".github/workflows/build-and-security.yml"
            }
        },
        "metadata": {
            "buildInvocationId": "placeholder",
            "buildStartedOn": datetime.now().isoformat(),
            "completeness": {
                "parameters": True,
                "environment": True,
                "materials": True
            },
            "reproducible": True
        }
    }
