-- What a bottle cost, in integer cents, on purchase rows only. Drink rows
-- read the price of the purchase they draw from.
ALTER TABLE cellar ADD COLUMN price_cents INTEGER;
