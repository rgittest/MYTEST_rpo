
select * from sys.procedures where name like '%segmententry__FFMDE%'


sp_helptext prcAdd_SegmentEntry__FFMDE


Use ffdam


select isnull(wt.DisplayName,'GrandTotal') as Task,count(d.id) as Total from ffdam..workqueue w (nolock)
join ffdam..workqueuetasks wt (nolock) on wt.id=w.taskid
join ffdam..documents d (nolock) on d.id=w.documentid
where wt.Name in ('MultiMeta','HLangId','DupeQA','MetadataQA','SdrMdaMrge','Resolution','FFResolutinoVerification','PageRotate') and w.WaitCount=0 --**********include Single Entry Enhancement row with 
group by cube(wt.DisplayName);


--select top 10 * from documents

-- Above querry specifies that a single task 



--select  * from WorkQueueTasks where Name in ('MultiMeta','HLangId','DupeQA','MetadataQA','SdrMdaMrge','Resolution','FFResolutinoVerification','PageRotate')

--select  * from WorkQueueTasks

--select  * from Groups where name ='MultipleEntry_GroupA'


  --select  * from Groups where name ='MultipleEntry_GroupB'


  --select count (*) from Groups 
  

 select top 10 * from WorkQueueTasks

  
  
  select isnull(f.DisplayName,'GrandTotal') as Feed,sum(case when w.AssignedGroupId=263 then 1 else 0 end) as GroupA,sum(case when w.AssignedGroupId=264 then 1 else 0 end)  as GroupB,/* add Singlr Entry  Column */COUNT(d.id) as GrandTotal
from ffdam..documents d (nolock)
join ffdam..WorkQueue w (nolock) on d.id=w.documentid
join ffdam..workqueuetasks wt (nolock) on wt.id=w.taskid
join ffdam..feeds f (nolock) on f.id=d.FeedId
where wt.Name='MultiMeta' and w.assignedgroupid in (263,264) and w.WaitCount=0
group by cube(f.DisplayName);





select isnull(CONVERT(VARCHAR(10), w.AvailableStampUtc, 111),'GrandTotal') as AvailableStamp  ,sum(case when w.BasePriority>=1 then 1 else 0 end) As HighPriority,sum(case when w.BasePriority<1 then 1 else 0 end) As LowPriority , COUNT(d.id) as GrandTotal

from ffdam..documents d(nolock)
join ffdam..WorkQueue w (nolock) on w.documentid=d.id 
join ffdam..workqueuetasks wt (nolock) on wt.id=w.taskid 
where wt.name='MultiMeta' and w.WaitCount=0
group by cube((CONVERT(VARCHAR(10), w.AvailableStampUtc, 111)));







CREATE PROCEDURE dbo.prcAdd_SegmentEntry__FFMDE (@DocumentId uniqueidentifier, @RootId tinyint, @RunId smallint, @BasePriority real, @UserId int) AS
	IF @DocumentId IS NULL RAISERROR('Null argument error: @DocumentId. Non-null value expected', 11, 0)
	IF @RootId IS NOT NULL RAISERROR('Invalid argument: @RootId. NULL Expected', 11, 0)
	IF @RunId IS NULL RAISERROR('Null argument error: @RunId. Non-null value expected', 11, 0)
	IF @BasePriority IS NULL RAISERROR('Null argument error: @BasePriority. Non-null value expected', 11, 0)
	IF @UserId IS NULL RAISERROR('Null argument error: @UserId. Non-null value expected', 11, 0)
	
	EXEC prcAdd_GenericRelevancyTask @DocumentId, @UserId, @BasePriority, 'FFMDE'

	DECLARE @Feed VARCHAR(50), @Is8KFormType BIT = 0 
	DECLARE @NewVersionId UNIQUEIDENTIFIER
	DECLARE @PeriodEndDate DATETIME
	SELECT @Feed = SearchName FROM Documents WITH (NOLOCK) JOIN Feeds WITH (NOLOCK) ON Feeds.Id = Documents.FeedId WHERE Documents.Id = @DocumentId

	SELECT TOP 1 @Is8KFormType = 1 FROM dbo.DocumentFeedMeta dfm WITH (NOLOCK) Where dfm.DocumentId = @DocumentId and dfm.FeedKeyId = 12663 AND dfm.Value in ('8-K','8K','8K/A','8-K/A') --'FORM-TYPE'

	--Insert Period End date at Document level if it is not present || For 8-K formtype, just take it from root 0
	IF @Is8KFormType = 1
	BEGIN
		
		SELECT TOP 1 @PeriodEndDate = CONVERT(SMALLDATETIME , drm.Value) FROM dbo.DocumentRoots dr WITH (nolock)
		inner join dbo.DocumentRootMeta drm WITH (NOLOCK) on drm.DocumentRootVersionId = dr.CurrentVersion
		inner join dbo.MetaKeys mk WITH (NOLOCK) on mk.id = drm.KeyId
		WHERE dr.DocumentId = @DocumentId AND dr.RootId = 0 AND mk.Name = 'Period' AND ISDATE(drm.Value) = 1 AND drm.KeyIndex = 0

		IF EXISTS 
			(
				SELECT TOP 1 '1' FROM dbo.vw_DocumentMetaPivot WITH (NOLOCK) WHERE DocumentId = @DocumentId AND Period IS NULL
			) 
	AND
			@PeriodEndDate IS NOT NULL
		
		BEGIN

			EXEC dbo.prcAdd_CloneDocumentVersion @DocumentId , @UserId , @NewVersionId OUTPUT , 1 

			UPDATE dbo.Documents
			SET CurrentVersion = @NewVersionId
			WHERE id = @DocumentId
			
			UPDATE dbo.DocumentVersions
			SET PeriodEndDate = @PeriodEndDate
			WHERE DocumentId = @DocumentId AND VersionId = @NewVersionId

	   END
	END	
	ELSE
	BEGIN
		IF EXISTS 
			(
				SELECT '1' FROM dbo.vw_DocumentMetaPivot WITH (NOLOCK) WHERE DocumentId = @DocumentId AND Period IS NULL
			) 
		AND
			( 
				SELECT COUNT(DISTINCT CASE WHEN ISDATE (drm.Value) = 1 THEN CONVERT(SMALLDATETIME , drm.Value) ELSE NULL END) 
				FROM dbo.DocumentRoots dr WITH (nolock)
				inner join dbo.DocumentRootMeta drm WITH (NOLOCK) on drm.DocumentRootVersionId = dr.CurrentVersion
				inner join dbo.MetaKeys mk WITH (NOLOCK) on mk.id = drm.KeyId
				WHERE dr.DocumentId = @DocumentId AND mk.Name = 'Period' AND drm.KeyIndex = 0
		    ) = 1
			BEGIN
				
				SELECT TOP 1 @PeriodEndDate = CONVERT(SMALLDATETIME , drm.Value)
				FROM dbo.DocumentRoots dr WITH (nolock)
				inner join dbo.DocumentRootMeta drm WITH (NOLOCK) on drm.DocumentRootVersionId = dr.CurrentVersion
				inner join dbo.MetaKeys mk WITH (NOLOCK) on mk.id = drm.KeyId
				WHERE dr.DocumentId = @DocumentId AND mk.Name = 'Period' AND drm.KeyIndex = 0

				EXEC dbo.prcAdd_CloneDocumentVersion @DocumentId , @UserId , @NewVersionId OUTPUT , 1 

				UPDATE dbo.Documents
				SET CurrentVersion = @NewVersionId
				WHERE id = @DocumentId
			
				UPDATE dbo.DocumentVersions
				SET PeriodEndDate = @PeriodEndDate
				WHERE DocumentId = @DocumentId AND VersionId = @NewVersionId

		   END
	END

	INSERT WorkQueue (TaskId, DocumentId, BasePriority, AvailableStampUtc, CreatedByUserId, WqPath, RunId)			
	SELECT wqt.Id, @documentid, @BasePriority, getutcdate(), @userid, 'METAE', @RunId
	FROM WorkQueueTasks wqt (nolock)
	WHERE wqt.Name = 'LionCmpny'
	


	sp_helptext prcAdd_GenericRelevancyTask



CREATE PROCEDURE dbo.prcAdd_GenericRelevancyTask (@DocumentId uniqueidentifier, @UserId int, @BasePriority real, @Segment varchar(10)) AS
	DECLARE @FileId smallint	
	DECLARE @WqID uniqueidentifier
	DECLARE @ItemMeta dbo.WorkQueueMetaType

	SELECT @FileId= max(df.FileId) FROM dbo.DocumentFiles df WITH (NOLOCK)
	WHERE df.DocumentId = @DocumentId AND df.RootId=0 AND df.FileType= 'HTML' AND df.IsoLanguageId = 'ENG'

	--Skip when there no ENG HTML file available for root-0
	IF @FileId is NULL
		return;

	--Skip when document is already in queue
	IF exists (SELECT 'x' from dbo.WorkQueue w WITH (NOLOCK) JOIN dbo.WorkQueueTasks wt WITH (NOLOCK) ON w.TaskId=wt.id where DocumentId=@DocumentId and wt.Name='GenericRelevancy')
		return;

	--Skip when Generic relevancy application meta data already updated
	IF exists (SELECT dam.Value FROM dbo.DocumentApplicationMeta dam WITH (NOLOCK) 
	JOIN dbo.ApplicationMetaKeys amk WITH (NOLOCK) ON dam.ApplicationKeyId=amk.id
	join dbo.Applications a WITH (NOLOCK) ON a.Id=amk.ApplicationId 
	WHERE dam.DocumentId = @DocumentId and a.ShortName='GenericRelevancy' and amk.Name='IsGenericRelUpdated')
		return;

		 
	insert INTO @ItemMeta (TypeCode, KeyIndex, Value) VALUES ('QueuedFrom',0,@Segment)

	EXEC prcAdd_WorkQueueItemWithMeta  
			@_documentId = @DocumentId,  
			@_taskName = 'GenericRelevancy',  
			@_wqPath = null,  
			@_runId = null,  
			@_fileId = @FileId,
			@_basePriority = @BasePriority,  
			@_createdByUserId = @UserId,  
			@_assignedUserId = null,  
			@_assignedGroupId = null,  
			@_ignoresTime = 0,  
			@_meta = @ItemMeta, @_NewWqId = @WqID out  	

			
			
			
			
			
			
			
			
			
CREATE PROCEDURE dbo.prcAdd_WorkQueueItemWithMeta (
	@_documentId uniqueidentifier,
	@_taskName varchar(25),
	@_wqpath char(5),
	@_runId smallint,
	@_fileId smallint = NULL,
	@_BasePriority real = 1,
	@_AvailableStampUtc datetime = NULL,
	@_AssignedUserId int = NULL,
	@_AssignedGroupId int = null,
	@_CreatedByUserId int = NULL,
	@_WaitCount tinyint = 0,
	@_IgnoresTime bit = 0,
	@_Meta dbo.WorkQueueMetaType READONLY,
	@_NewWqId uniqueidentifier = NULL OUTPUT
) AS

	IF @_taskName is null 
		RAISERROR( N'Task Name provided is null!', 11, 1);

	DECLARE @TranCount INT = @@TRANCOUNT;
	IF (@TranCount = 0) BEGIN TRANSACTION;
	ELSE SAVE TRANSACTION WorkQueueItemMetaAddition;

	DECLARE @t TABLE ( id uniqueidentifier );
	BEGIN TRY
		INSERT WorkQueue ( DocumentId, TaskId, wqPath, runId, fileId, BasePriority, AvailableStampUtc, AssignedUserId, AssignedGroupId, CreatedByUserId, WaitCount, ignoresTime)
		OUTPUT INSERTED.id INTO @t ( id )
		SELECT @_documentId, wqt.Id, @_wqPath, @_runId, @_fileId, @_BasePriority, ISNULL(@_AvailableStampUtc, GETUTCDATE()), @_AssignedUserId, @_AssignedGroupId, @_CreatedByUserId, @_WaitCount, @_IgnoresTime
		FROM WorkQueueTasks wqt
		WHERE Name=@_taskName

		SET @_NewWqId = ( SELECT TOP 1 id FROM @t );

		IF @_NewWqId IS NULL BEGIN
			Declare @_errormsg nvarchar(256);
			Set @_errormsg = N'Failed to create a workqueue id, _NewWqid was null! _Taskname: ' + @_taskName;
			RAISERROR ( @_errormsg, 11, 1 );
		END

		INSERT WorkQueueMeta ( WorkQueueId, TypeId, KeyIndex, Value )
		SELECT @_NewWqId, wqmt.id, m.KeyIndex, m.Value
		FROM @_meta m JOIN
			WorkQueueMetaTypes wqmt on m.TypeCode = wqmt.Code

		IF (@TranCount = 0) COMMIT TRANSACTION;

	END TRY
	BEGIN CATCH		
		DECLARE @TranState SMALLINT = XACT_STATE();
		IF (@TranState IN (-1, 1) AND @TranCount = 0) ROLLBACK TRANSACTION;
		ELSE IF (@TranState = 1 AND @TranCount > 0) ROLLBACK TRANSACTION WorkQueueItemMetaAddition;

		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
		DECLARE @ErrorState INT = ERROR_STATE();
		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);	

	END CATCH;	

	RETURN 0
	
	
	
	
	
	
--------------------------------------------------------------------------------
-- dbo.prcAdd_CloneDocumentVersion
--
-- PURPOSE:
-- Copies metadata and companies from the current document meta version.
--
-- HISTORY:
-- 2009-06-05 mhurwitz: Created.
-- 2010-02-10 mhurwitz: Added PeriodEndDate support.
-- 2010-04-27 siannelli: added option to not clone companies
--------------------------------------------------------------------------------
CREATE PROCEDURE dbo.prcAdd_CloneDocumentVersion (
	@documentid uniqueidentifier, 
	@userid int, 
	@newversionid uniqueidentifier OUTPUT,
	@cloneCompanies bit = 1
) AS

DECLARE	@oldversionid uniqueidentifier
SELECT	@oldversionid = currentversion FROM Documents WHERE id = @documentid

IF @oldversionid IS NULL RETURN -1
IF NOT EXISTS (SELECT 'x' FROM Users WHERE id = @userid AND active = 1) RETURN -1

DECLARE @IDs TABLE (id uniqueidentifier not null)

BEGIN TRAN
INSERT	DocumentVersions (DocumentId, UpdateStampUtc, UserId, PeriodEndDate)
OUTPUT  INSERTED.VersionId INTO @IDs
SELECT	DocumentId, GetUtcDate(), @userid, PeriodEndDate
FROM	DocumentVersions
WHERE	VersionId = @oldversionid AND 
	DocumentId = @DocumentId

SELECT @newversionid = id FROM @IDs

INSERT	DocumentVersionMeta (DocumentVersionId, KeyId, KeyIndex, [Value])
SELECT	@newversionid, KeyId, KeyIndex, [Value]
FROM	DocumentVersionMeta
WHERE	DocumentVersionId = @oldversionid

IF @cloneCompanies = 1 BEGIN
	INSERT	DocumentVersionCompanies (DocumentVersionId, Iconum, IsPrimary, Confidence)
	SELECT	@newversionid, Iconum, IsPrimary, Confidence
	FROM	DocumentVersionCompanies
	WHERE	DocumentVersionId = @oldversionid
END

COMMIT TRAN

RETURN 0










CREATE PROCEDURE dbo.prcAdd_WorkQueueFlow__LionCmpny__METAE (@SrcWqId UNIQUEIDENTIFIER) 
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @IDs TABLE (ix INT IDENTITY(1,1) NOT NULL, 
						id UNIQUEIDENTIFIER NOT NULL, 
						TaskName VARCHAR(20) NULL);
	DECLARE @CompletionStatus INT,
			@DocumentId UNIQUEIDENTIFIER,
			@UserId INT,
			@RunId SMALLINT,
			@BasePriority REAL,
			@RetVal INT,
			@SrcVersion UNIQUEIDENTIFIER,
			@IsRFFDocument BIT = 0,
			@IsMissingMetadata INT,
			@GroupA INT,
			@GroupB INT,
			@SingleGroup INT,
			@parallelRunId SMALLINT	,
			@MetaAWorkQueueId NVARCHAR(50),
			@MetabWorkQueueId NVARCHAR(50),
			@MetaWorkQueueId NVARCHAR(50);
				
	SELECT 
		@CompletionStatus = CompletionStatus,
		@DocumentId = DocumentId,
		@UserId = UserId,
		@RunId = RunId,
		@BasePriority = BasePriority
	FROM dbo.WorkQueueHistory WITH (NOLOCK)
	WHERE Id = @SrcWqId;

	-- EngFail on any error that isn't AgentFail (which can be thrown for benign reasons)
	IF @CompletionStatus < 0 AND @CompletionStatus != -50
	BEGIN
		EXEC prcAdd_WorkQueueAgentCodeFailure @SrcWqId, 'Task completed with a negative status, not AgentFail.';
	END
	ELSE 
	BEGIN
		-- Continue if Document is Valid & Relevant
		EXEC @IsMissingMetadata = prcGet_ValidateDocument @DocumentId;	
		IF @IsMissingMetadata != 0
		BEGIN

			-- Use current document version as the source version for users to work from
			SELECT @SrcVersion = CurrentVersion FROM dbo.Documents d WITH (NOLOCK) WHERE d.id=@DocumentId;

			SELECT  TOP 1 @IsRFFDocument = 1
			FROM dbo.Documents d WITH (NOLOCK) 
			INNER JOIN dbo.Feeds f WITH (NOLOCK) on d.FeedId = f.id and d.id = @DocumentId
			LEFT JOIN dbo.DocumentFeedMeta dfm WITH (NOLOCK) on dfm.DocumentId = d.id and dfm.FeedKeyId = 12663 --'FORM-TYPE'
			LEFT JOIN dbo.DocumentFeedMeta dfm1 WITH (NOLOCK) on dfm1.DocumentId = d.id and dfm1.FeedKeyId IN (10610,37793)--'category'
			Where
			(
				f.SearchName  IN ('BW','INW','PMZ','PRN','TDT','SDR','SGX','VIET','JSE','NZX','PRNA','PRNE')
				OR
				(f.SearchName  = 'EDG' AND dfm.Value IN ('8-K','8K','8K/A','8-K/A'))   
				OR
				(f.SearchName  = 'UKW' AND dfm1.Value ='FR')				
			);

			IF (@IsRFFDocument = 1)
			BEGIN
				-- SingleEntry Group Metadata Enhancement 
				SELECT @SingleGroup = id FROM dbo.Groups WITH (NOLOCK) WHERE Name='SingleEntry_MDE';

				INSERT WorkQueue (TaskId, BasePriority, DocumentId, AvailableStampUtc, AssignedGroupId, CreatedByUserId, WqPath, RunId)
				OUTPUT INSERTED.ID, 'MetaEnhanc' INTO @IDs (id, TaskName)
				SELECT id, @BasePriority, @DocumentId, GETUTCDATE(), @SingleGroup, @UserId, 'SEMM', @runId
				FROM dbo.WorkQueueTasks WITH (NOLOCK)
				WHERE Name = 'MultiMeta';

				SELECT @MetaWorkQueueId = MyIDs.id FROM @IDs [MyIDs] WHERE MyIDs.TaskName = 'MetaEnhanc';
				EXEC dbo.prcAdd_WorkQueueItemMeta @ItemId=@MetaWorkQueueId, @TypeCode='SrcVersion', @Value=@SrcVersion;
			END
			ELSE
			BEGIN
				EXEC prcAdd_RunWithParallelTasks @DocumentId, NULL, @RunId, 'METAE', @BasePriority, @UserId, @parallelRunId OUT;

				-- Multiple Entry Metadata Enhancement (Group A)
				SELECT @GroupA = id FROM dbo.Groups WITH (NOLOCK) WHERE Name='MultipleEntry_GroupA';

				INSERT WorkQueue (TaskId, BasePriority, DocumentId, AvailableStampUtc, AssignedGroupId, CreatedByUserId, WqPath, RunId)
				OUTPUT INSERTED.ID, 'MetaEnhancA' INTO @IDs (id, TaskName)
				SELECT id, @BasePriority, @DocumentId, GETUTCDATE(), @GroupA, @UserId, 'METAE', @parallelRunId
				FROM dbo.WorkQueueTasks WITH (NOLOCK)
				WHERE Name = 'MultiMeta';

				SELECT @MetaAWorkQueueId = MyIDs.id FROM @IDs [MyIDs] WHERE MyIDs.TaskName = 'MetaEnhancA';
				EXEC dbo.prcAdd_WorkQueueItemMeta @ItemId=@MetaAWorkQueueId, @TypeCode='SrcVersion', @Value=@SrcVersion;

				-- Multiple Entry Metadata Enhancement (Group B)
				SELECT @GroupB=id FROM dbo.Groups WITH (NOLOCK) WHERE Name='MultipleEntry_GroupB';

				INSERT WorkQueue (TaskId, BasePriority, DocumentId, AvailableStampUtc, AssignedGroupId, CreatedByUserId, WqPath, RunId)
				OUTPUT INSERTED.ID, 'MetaEnhancB' INTO @IDs (id, TaskName)
				SELECT id, @BasePriority, @DocumentId, GetUtcDate(), @GroupB, @UserId, 'METAE', @parallelRunId
				FROM dbo.WorkQueueTasks WITH (NOLOCK)
				WHERE Name = 'MultiMeta';

				SELECT @MetaBWorkQueueId = MyIDs.id FROM @IDs MyIDs WHERE MyIDs.TaskName = 'MetaEnhancB';
				EXEC dbo.prcAdd_WorkQueueItemMeta @ItemId=@MetaBWorkQueueId, @TypeCode='SrcVersion', @Value=@SrcVersion;
		
			END 
		END
		ELSE
		BEGIN
			EXEC prcUpd_WorkFlowAction_EndSegment;
		END
	END	
END

			
			
			

			

