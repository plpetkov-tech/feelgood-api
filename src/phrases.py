"""Phrase generator module"""
import random
from typing import List, Optional, Tuple


class PhraseGenerator:
    """Generates feel-good phrases by category"""
    
    def __init__(self):
        self.phrases = {
            "motivation": [
                "You are capable of amazing things!",
                "Every day is a new beginning.",
                "Believe in yourself and all that you are.",
                "Your potential is endless.",
                "You've got this!"
            ],
            "gratitude": [
                "Today is a gift, that's why it's called the present.",
                "Gratitude turns what we have into enough.",
                "Count your rainbows, not your thunderstorms.",
                "The little things are the big things.",
                "Appreciation is a wonderful thing."
            ],
            "kindness": [
                "Kindness is always fashionable.",
                "Be the reason someone smiles today.",
                "A little kindness goes a long way.",
                "Spread love everywhere you go.",
                "Your kindness makes a difference."
            ],
            "growth": [
                "Progress, not perfection.",
                "Every expert was once a beginner.",
                "Growth happens outside your comfort zone.",
                "You're becoming who you're meant to be.",
                "Small steps lead to big changes."
            ]
        }
    
    def get_phrase(self, category: Optional[str] = None) -> Tuple[str, str]:
        """Get a random phrase, optionally from a specific category"""
        if category:
            if category not in self.phrases:
                raise ValueError(f"Category '{category}' not found. Available: {list(self.phrases.keys())}")
            return random.choice(self.phrases[category]), category
        
        # Random category if none specified
        category = random.choice(list(self.phrases.keys()))
        return random.choice(self.phrases[category]), category
    
    def get_categories(self) -> List[str]:
        """Get all available categories"""
        return list(self.phrases.keys())
