package com.shoplite.catalogue;

public record Product(int id, String name, String description, int priceCents, String category, String emoji, int stock) {
}
