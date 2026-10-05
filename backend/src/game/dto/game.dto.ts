import { IsIn, IsInt, Max, Min } from 'class-validator';

/** Item codes seeded in database/04_seed.sql (must match Godot ItemCodes). */
export const ITEM_CODES = ['pvc_straight', 'pvc_90_deg', 'pvc_tee', 'teflon_tape'] as const;
export const PLACEABLE_CODES = ['pvc_straight', 'pvc_90_deg', 'pvc_tee'] as const;

export class CompleteJobDto {
  @IsIn(PLACEABLE_CODES)
  itemCode!: string;

  @IsInt()
  @Min(1)
  @Max(86400)
  timeSeconds!: number;

  @IsInt()
  @Min(0)
  @Max(500)
  partsUsed!: number;

  @IsInt()
  @Min(0)
  @Max(500)
  partsWasted!: number;
}

export class PurchaseDto {
  @IsIn(ITEM_CODES)
  itemCode!: string;

  @IsInt()
  @Min(1)
  @Max(100)
  quantity!: number;
}

export class UpgradeVehicleDto {
  @IsInt()
  @Min(2)
  @Max(4)
  tierId!: number;
}
