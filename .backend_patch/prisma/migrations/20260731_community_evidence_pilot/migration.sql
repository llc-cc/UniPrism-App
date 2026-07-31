ALTER TABLE `content_ingestion_batches`
  ADD COLUMN `stageMetrics` JSON NULL;

CREATE TABLE `community_evidence_analyses` (
  `id` VARCHAR(191) NOT NULL,
  `contentItemId` VARCHAR(191) NOT NULL,
  `institutionCode` VARCHAR(80) NOT NULL,
  `institutionName` VARCHAR(160) NOT NULL,
  `majorName` VARCHAR(160) NULL,
  `platform` VARCHAR(40) NOT NULL,
  `dimension` VARCHAR(40) NOT NULL,
  `qualityScore` INTEGER NOT NULL,
  `credibilityScore` DECIMAL(4, 2) NULL,
  `similarityHash` CHAR(16) NOT NULL,
  `duplicateClusterId` VARCHAR(191) NULL,
  `spamSignals` JSON NULL,
  `privacyFlags` JSON NULL,
  `sentiment` JSON NULL,
  `claims` JSON NULL,
  `analysisStatus` VARCHAR(40) NOT NULL DEFAULT 'rules_passed',
  `model` VARCHAR(120) NULL,
  `promptVersion` VARCHAR(80) NULL,
  `reviewerUserId` VARCHAR(191) NULL,
  `reviewedAt` DATETIME(3) NULL,
  `reviewNote` TEXT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
    ON UPDATE CURRENT_TIMESTAMP(3),

  UNIQUE INDEX `community_evidence_analyses_contentItemId_key`(`contentItemId`),
  INDEX `community_evidence_analyses_institution_dimension_status_idx`
    (`institutionCode`, `dimension`, `analysisStatus`),
  INDEX `community_evidence_analyses_platform_createdAt_idx`
    (`platform`, `createdAt`),
  INDEX `community_evidence_analyses_duplicateClusterId_idx`
    (`duplicateClusterId`),
  PRIMARY KEY (`id`),
  CONSTRAINT `community_evidence_analyses_contentItemId_fkey`
    FOREIGN KEY (`contentItemId`) REFERENCES `content_items`(`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
