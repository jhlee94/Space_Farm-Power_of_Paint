#include "../../GameConfig/GameConfig.h"
#ifndef SHOULD_LOAD_SANDBOX_APPLICATION

#include <../Samples/Common/PhyreSamplesCommonScene.cpp>

using namespace Phyre;
using namespace PFramework;
using namespace PRendering;
#ifdef PHYRE_ENABLE_PHYSICS
using namespace PPhysics;
#endif // PHYRE_ENABLE_PHYSICS
#ifdef PHYRE_ENABLE_AUDIO
using namespace PAudio;
#endif //! PHYRE_ENABLE_AUDIO
using namespace PInputs;
using namespace PGameplay;
using namespace PCharacter;
using namespace PWorldRendering;
using namespace PScene;
using namespace PNavigation;
using namespace PText;
using namespace PSamplesCommon;
using namespace Vectormath::Aos;

// Description:  
// The static sample application instance (either game or sandbox will be loaded. See
// the #define in GameConfig.h) 
static GameApplication s_gameApp;

GameApplication &GameApplication::GetInstance()
{
	return s_gameApp;
}

PHYRE_BIND_START(GameApplication)
	PHYRE_BIND_METHOD(getWidth)
	PHYRE_BIND_METHOD(getHeight)
	PHYRE_BIND_METHOD(onPickupEnter)
	PHYRE_BIND_METHOD(pickupBoost)
PHYRE_BIND_END

// Description:
// The constructor for the PBasicSample class.
GameApplication::GameApplication()
	: m_renderViewports(true)
	, m_playerStartCount(0)
	, m_navMesh(NULL)
	, m_navigationDebug(false)
	, m_physicsDebug(false)
	, m_currentLevelCluster(NULL)
	, m_targets(NULL)
	, m_nextTargetID(0)
{
	setWindowTitle("Team 2 Game Application");
	setReadmeDirectory("./");

	// Initialise shadow maps with NULL
	for (PUInt32 i = 0; i < c_shadowMapMaxCount; ++i)
		m_shadowMaps[i] = NULL;

	// Hide Debug GUI
	m_showImGui = false;

#ifdef PHYRE_ENABLE_PHYSICS
	PUtility::RegisterUtility(PPhysics::s_utilityPhysics);
#endif //! PHYRE_ENABLE_PHYSICS

#ifdef PHYRE_ENABLE_AUDIO
	PUtility::RegisterUtility(PAudio::s_utilityAudio);
	//volume control initilisation
	m_volumeMultiplier = 0.15f;
	m_Volume = 1.0f;
	m_clockPlaying = false;
	m_clockStarted = false;
	m_movePlaying = false;
	m_moveStarted = false;
	m_music1Playing = false;
	m_music1Started = false;
	m_music2Playing = false;
	m_music2Started = false;
	m_music3Playing = false;
	m_music3Started = false;
#endif //! PHYRE_ENABLE_AUDIO

	PUtility::RegisterUtility(PScene::s_utilityScene);
	PUtility::RegisterUtility(PScripting::s_utilityScripting);
	PUtility::RegisterUtility(PEvent::s_utilityEvent);
	PUtility::RegisterUtility(PInputs::s_utilityInputs);
	PUtility::RegisterUtility(PAnimation::s_utilityAnimation);
	PUtility::RegisterUtility(PGameplay::s_utilityGameplay);
	PUtility::RegisterUtility(PCharacter::s_utilityCharacter);
	PUtility::RegisterUtility(PNavigation::s_utilityNavigation);
	PUtility::RegisterUtility(PText::s_utilityText);
}

Phyre::PResult GameApplication::prePhyreInit()
{
	GameApplication::Bind();
	// Set the correct application type so that scripts can get it.
	SetApplicationType(PHYRE_CLASS(GameApplication));
	return PSuper::prePhyreInit();
}

// Description:
// Initialize the application.
// Arguments:
// argv - Array of strings representing command line arguments. This does not include program name.
// argc - Length of argv string array.
// Return Value List:
// Other - An error occurred initializing the application.
// PE_RESULT_NO_ERROR - The application was initialized successfully.
PResult GameApplication::initApplication(PChar **argv, PInt32 argc)
{
	// Remove warning of not using argv & argc
	(void)argv;
	(void)argc;

	// Set the media directory to where we will be loading our data from (relative to the working directory).
	PhyreOS::SetMediaDirectory("..\\Media\\");

	// Init input map
	initInputMap();

	// Init Script Scheduler
	m_scheduler = PHYRE_NEW PScripting::PScheduler();
	if (m_scheduler)
		PHYRE_TRY(m_scheduler->initialize(256 * 1024, 2, 256 * 1024));

	// Load Assets into Cluster
	PHYRE_TRY(PCluster::LoadAssetFile(m_currentLevelCluster, "..\\Media\\" PHYRE_PLATFORM_ID "/Game.phyre"));

	// Resolve asset references and fixup instances
	PHYRE_TRY(FixupClusters(&m_currentLevelCluster, 1));

	// Spawner
	if (m_currentLevelCluster)
		PGameplay::PSpawner::Initialize(*m_currentLevelCluster, *m_scheduler, m_physicsWorld, m_sceneContext, m_budgetBlock[2]);

	//Physics
	PPhysicsInterfaceConfiguration physicsConfig;
	//If spu enabled (in ps3)
#ifdef PHYRE_SPU_ENABLED
	physicsConfig.m_numSPUs = 1;
#endif
	physicsConfig.m_scheduler = m_scheduler;
	PPhysicsInterface &physicsInterface = PPhysicsInterface::GetInstance();
	physicsInterface.initialize(physicsConfig);
	m_physicsWorld = PHYRE_NEW PPhysics::PPhysicsWorld();
	if (!m_physicsWorld)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OUT_OF_MEMORY, "Unable to allocate physics world.");
	PHYRE_TRY(m_physicsWorld->initialize());

#ifdef PHYRE_ENABLE_AUDIO
	// Use callbacks for allocations. 
	PAudio::PAudioInterface &audio = PAudio::PAudioInterface::GetInstance();

	// Setting the media directory is not strictly necessary as PhyreEngine
	// *should* check the primary asset directory in addition to the directory
	// set explicitly here. It has been done here for completeness.
	//PChar scePhyre[1024];
	//PhyreOS::GetCurrentDir(scePhyre, sizeof(scePhyre) - 1);
	PStringBuilder mediaDir(PhyreOS::GetMediaDirectory());

	// Tidy this up!
	//mediaDir += ""
	// Audio system might need different directory?
	// Initialize the audio system
	PHYRE_TRY(audio.initialize(mediaDir.c_str()));

#endif //! PHYRE_ENABLE_AUDIO

	// Initialize gui.
	PHYRE_TRY(PImGui::Initialize(getWidth(), getHeight()));

	return PE_RESULT_NO_ERROR;
}

// Description:
// Exit the application.
// Return Value List:
// Other - An error occurred exiting the application.
// PE_RESULT_NO_ERROR - The application was exited successfully.
PResult GameApplication::exitApplication()
{
	// Shutdown gui.
	PImGuiDebug::Terminate();
	PImGui::Terminate();

	// Free the loaded cluster
	delete m_currentLevelCluster;

	PHYRE_TRY(m_physicsWorld->syncSimulation());
	// Stop Physics
	{m_physicsWorld->terminate();
	PPhysicsInterface &physicsInterface = PPhysicsInterface::GetInstance();
	PHYRE_TRY(physicsInterface.terminate());}
	delete m_physicsWorld;

	// Stop Script Scheduler
	//m_scheduler->terminate();
	delete m_scheduler;

	PSpawner::Terminate();

	// Shutdown Audio system.
#ifdef PHYRE_ENABLE_AUDIO	
	// Terminate the audio utility.
	PAudio::PAudioInterface &audio = PAudio::PAudioInterface::GetInstance();
	PHYRE_TRY(audio.terminate());
#endif //! PHYRE_ENABLE_AUDIO	

	return PApplication::exitApplication();
}

// Description:
// Initialize the scene in preparation for rendering.
// Return Value List:
// Other - The scene initialization failed.
// PE_RESULT_NO_ERROR - The scene initialization succeeded.
PResult GameApplication::initScene()
{
	// Add lights to the scene from the level
	PSamplesCommon::PopulateSceneContextWithLights(m_sceneContext, *m_currentLevelCluster);

	// Add cluster to world.
	m_world.addCluster(*m_currentLevelCluster);

	// Find Locators
	{PHYRE_TRY(gatherLocators(*m_currentLevelCluster, m_enemyAILocators, "EnemyAI"));
	PHYRE_TRY(gatherLocators(*m_currentLevelCluster, m_targetLocators, "Target"));
	PHYRE_TRY(gatherLocators(*m_currentLevelCluster, m_playerLocators, "Player"));
	PHYRE_TRY(gatherLocators(*m_currentLevelCluster, m_playerStartLocators, "PlayerStart"));
	PHYRE_TRY(gatherLocators(*m_currentLevelCluster, m_pickUpLocators, "PickUp"));}

	// Check if player exist
	{m_playerStartCount = m_playerStartLocators.getCount();
	if (!m_playerStartCount)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "No PlayerStart points were found in the level");}

	// Spawn Pick ups on Locators
	//spawnPickUps();

	// Navigation
	{m_enemyAICount = m_enemyAILocators.getCount();
	m_targetCount = m_targetLocators.getCount();
	m_playerCount = m_playerLocators.getCount();

	if (!m_enemyAICount)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "No EnemyAI points were found in the level");
	if (!m_targetCount)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "No Target points were found in the level");
	if (!m_playerCount)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "No Player points were found in the level");

	// Ensure that the specified locators represent points on the surface of the loaded navmesh.
	// In the case of the target locators, we want to allocate some target components for the agents to navigate to.
	m_navMesh = PSamplesCommon::FindFirstInstanceInCluster<PNavigation::PNavMesh>(*m_currentLevelCluster);
	//m_navMesh The navigation mesh found in the loaded level
	if (!m_navMesh)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "No navigation mesh was found in the level");

	m_targets = m_currentLevelCluster->create<PNavigation::PNavigationTargetComponent>(m_targetCount);
	m_moving_targets = m_currentLevelCluster->create<PNavigation::PNavigationTargetComponent>(m_playerCount);
	PHYRE_TRY(attachLocatorsToNavMesh(*m_currentLevelCluster, *m_navMesh, m_enemyAILocators, NULL));
	PHYRE_TRY(attachLocatorsToNavMesh(*m_currentLevelCluster, *m_navMesh, m_targetLocators, m_targets));
	PHYRE_TRY(attachLocatorsToNavMesh(*m_currentLevelCluster, *m_navMesh, m_playerLocators, m_moving_targets));

	// The bots are instantiated based on the first mesh instance in the loaded Bot cluster
	const PMeshInstance	*botInstance = FindAssetRefObj<PMeshInstance>(NULL, "character_bot.dae");
	if (!botInstance)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "No bot mesh instance was found in the bot file");

	float botRadius = 1.0f;
	float botHeight = 1.0f;
	const PMeshInstanceBounds *botBounds = botInstance->getBounds();
	if (botBounds)
	{
		Vector3 size = botBounds->getSize();
		botHeight = size.getY();
		float x = size.getX();
		float z = size.getZ();
		botRadius = 0.5f * sqrtf(x * x + z * z);
	}

	PResult result = PNavigation::PUtilityNavigation::InitializeCrowd(*m_navMesh, BOT_COUNT + 1, botRadius);
	if (result != PE_RESULT_NO_ERROR)
		return PHYRE_SET_LAST_ERROR(result, "Failed to initialize crowd");

	// To instantiate a Bot, we create a new PMeshInstance based on the PMesh used by the Bot cluster
	PInstanceList *botIL = m_currentLevelCluster->allocateInstanceFreeList(BOT_COUNT, PHYRE_CLASS(PMeshInstance));
	if (!botIL)
		return PE_RESULT_OUT_OF_MEMORY;
	for (PUInt32 i = 0; i < BOT_COUNT; i++)
	{
		Bot &bot = m_bots[i];

		Vector3	startingPosition = m_enemyAILocators[i % m_enemyAICount]->getLocalToWorldMatrix()->getMatrix().getTranslation();
		PWorldMatrix *newBotWorldMatrix = m_currentLevelCluster->create<PWorldMatrix>(1);
		newBotWorldMatrix->getMatrix().setTranslation(startingPosition);

		PHYRE_TRY(cloneMeshInstanceSimple(*m_currentLevelCluster, *botInstance, *newBotWorldMatrix, *botIL));

		bot.m_entity.setWorldMatrix(newBotWorldMatrix);

		// To use the PNavigationCrowdAgentComponent we have to add it to the crowd maintained by PUtilityNavigation
		// The agent requires at least a known height and a start position
		// A PUtilityNavigation::AddAgentToCrowd() overload exists that accepts more parameters for the agent
		// Calling setScaleFromWorldMatrix() extracts the scale from the entity's matrix so that it can be reapplied to the world matrix when reconstructing during updates
		PNavigation::PNavigationCrowdAgentComponent *navigationComponent = m_currentLevelCluster->create<PNavigation::PNavigationCrowdAgentComponent>(1);
		bot.m_entity.addComponent(*navigationComponent);
		navigationComponent->setMaximumSpeed(5.0f); //bot speed
		PNavigation::PUtilityNavigation::AddAgentToCrowd(botHeight, startingPosition, *navigationComponent);
		navigationComponent->setTarget(&m_targets[i % m_targetCount]);
		navigationComponent->setScaleFromWorldMatrix();

		bot.m_worldMatrix = newBotWorldMatrix;
		bot.m_navigationTarget = m_currentLevelCluster->create<PNavigation::PNavigationTargetComponent>(1);
		bot.m_navigationComponent = navigationComponent;
	}

	PBoundsAggregator &levelBounds = m_levelBounds;
	levelBounds.aggregateBounds(*m_currentLevelCluster);

	// The floaters are instantiated based on the first mesh instance in the loaded Floater cluster
	// Each floater is initialized in a position that distributes them on a grid in the level
	const PMeshInstance    *floaterInstance = FindAssetRefObj<PMeshInstance>(NULL, "floater_bot.dae");
	if (!floaterInstance)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "No floater mesh instance was found in the floater file");

	Vector3 levelSize = levelBounds.getMax() - levelBounds.getMin();
	levelSize.setY(0.0f);
	Vector3 floaterAreaBounds = levelSize / FLOATER_SQUARE_ROOT;
	Vector3 floaterAreaCorner(0.0f);
	Vector3 floaterAreaX = mulPerElem(floaterAreaBounds, Vector3::xAxis());
	Vector3 floaterAreaZ = mulPerElem(floaterAreaBounds, Vector3::zAxis());
	Floater *floater = m_floaters;

	dtNavMeshQuery		query;
	if (!dtStatusSucceed(query.init(m_navMesh->m_navMesh, 1)))
		return PE_RESULT_UNKNOWN_ERROR;
	PInstanceList *floaterIL = m_currentLevelCluster->allocateInstanceFreeList(FLOATER_COUNT, PHYRE_CLASS(PMeshInstance));
	if (!floaterIL)
		return PE_RESULT_OUT_OF_MEMORY;
	for (PUInt32 i = 0; i < FLOATER_SQUARE_ROOT; i++, floaterAreaCorner += floaterAreaX)
	{
		for (PUInt32 j = 0; j < FLOATER_SQUARE_ROOT; j++, floater++, floaterAreaCorner += floaterAreaZ)
		{
			floater->m_boundsMin = levelBounds.getMin() + floaterAreaCorner;
			floater->m_boundsSize = floaterAreaBounds;

			Vector3	startingPosition = floater->m_boundsMin + 0.5f * floaterAreaBounds;
			PNavigation::PNavigationTargetComponent startingTarget;
			startingTarget.update(query, startingPosition);
			PWorldMatrix *newFloaterWorldMatrix = m_currentLevelCluster->create<PWorldMatrix>(1);
			newFloaterWorldMatrix->getMatrix().setTranslation(startingTarget.getPosition());

			PHYRE_TRY(cloneMeshInstanceSimple(*m_currentLevelCluster, *floaterInstance, *newFloaterWorldMatrix, *floaterIL));
			floater->m_entity.setWorldMatrix(newFloaterWorldMatrix);

			// To use the PNavigationPathFollowingComponent we only have to add if to the entity whose matrix represents the target which gets updated when animating
			PNavigation::PNavigationPathFollowingComponent *navigationComponent = m_currentLevelCluster->create<PNavigation::PNavigationPathFollowingComponent>(1);
			floater->m_entity.addComponent(*navigationComponent);
			navigationComponent->setScaleFromWorldMatrix();

			//floater speed
			navigationComponent->setMaximumSpeed(5.0f);

			floater->m_navigationComponent = navigationComponent;
		}
		floaterAreaCorner.setZ(0.0f);
	}
	PHYRE_ASSERT(floater == &m_floaters[PHYRE_STATIC_ARRAY_SIZE(m_floaters)]);}

	// Retrieve and use game config. // This is not neccessary 
	{PGame::PGameConfig *gameConfig = NULL;
	PCluster *gameConfigCluster = NULL;

	if (m_currentLevelCluster)
	{
		PCluster::PObjectIteratorOfType<PGame::PGameConfig> configIt(*m_currentLevelCluster);
		gameConfig = configIt ? &*configIt : NULL;
		gameConfigCluster = m_currentLevelCluster;
	}

	if (gameConfig)
	{
		// Activate input map referenced in settings.
		PInputMap* inputMap = gameConfig->getInputMap();
		if (inputMap)
		{
			inputMap->setCluster(*gameConfigCluster);
			getInputMapper().setInputMap(inputMap);
		}
	}}

	// Lights
	{m_lightCount = 0;
	// Work with point lights
	for (PWorld::PConstObjectIteratorOfType<PRendering::PLight> itLight(m_world); itLight; ++itLight)
		m_lightCount++;
	// Allocate size of light array and fill it with the lights from the world
	m_pointLights.resize(PARRAY_ALLOCSITE m_lightCount);
	const PRendering::PLight **light = m_pointLights.getArray();
	for (PWorld::PConstObjectIteratorOfType<PRendering::PLight> it(m_world); it; ++it)
		//Keep the directional light in a separate variable
		if (it->getLightType() == PHYRE_GET_LIGHT_TYPE(PRendering::DirectionalLight)) {
			m_directionalLight = &*it;
			m_lightCount--;
		}
		else
			*light++ = &*it;
	}

	// Shadow
	{// Allocate the shadow map render targets
		for (PUInt32 i = 0; i < c_shadowMapMaxCount; ++i)
		{
			PRenderTarget *shadowMap = PShadowRenderer::AllocateShadowRenderTarget(m_shadowCluster, c_shadowMapSize);
			m_shadowMaps[i] = shadowMap;
		}

		// Add the shadow cluster to the world.
		m_world.addCluster(m_shadowCluster);}

	// Texts Setup
	{
	}

	// Configure Viewport
	configureViewports();

	// Initialize all the scriptable components.
	PInt32 camera_index = 0, player_count = 0;
	for (PWorld::PObjectIteratorOfType<PScriptableComponent> it(m_world); it; ++it) {
		PScriptableComponent &component = *it;

		// Get the entity so we can then get the other objects.
		PEntity *entity = component.getEntity();

		// Find the PPhysicsCharacterControllerComponents to set up the physics.
		if (component.getComponentType().isTypeOf(PHYRE_CLASS(PPhysicsCharacterControllerComponent))) {
			PCharacter::PPhysicsCharacterControllerComponent &controller = static_cast<PPhysicsCharacterControllerComponent &>(component);
			// Set Character Controllers.
			if (player_count < m_playerStartCount) {
				// Set controller
				m_characterControllers[player_count] = &controller;
				controller.setPhysicsWorld(m_physicsWorld);
				// Set controller start position
				m_characterControllers[player_count]->setStartPosition(
					static_cast<Point3>(m_playerStartLocators[player_count]->getLocalToWorldMatrix()->getMatrix().getTranslation()));
				player_count++;
			}
		}

		// Do camera controller specific setup.
		if (component.getComponentType().isTypeOf(PHYRE_CLASS(PCameraControllerComponent))) {
			// We have to convert PChar* to PString because apparently PChar* comparison does not work -_-;
			PEntity *entity = component.getEntity();
			PNameComponent* name = entity->getComponentOfType<PNameComponent>();
			PString sname(name->getName());
			if (sname == "Overview") {
#ifdef USE_OVERVIEW_CAMERA
				PCameraControllerComponent *camera = static_cast<PCameraControllerComponent *>(&component);
				camera->initializePhysics(m_physicsWorld);
				m_cameras[m_playerStartCount - 1] = (static_cast<PCameraPerspective *>((camera->getCamera())));
#endif
			}
			else if (camera_index < m_playerStartCount) {
				PCameraControllerComponent *camera = static_cast<PCameraControllerComponent *>(&component);
				camera->initializePhysics(m_physicsWorld);
				m_cameraControllers[camera_index] = camera;
				m_cameras[camera_index] = (static_cast<PCameraPerspective *>((camera->getCamera())));
				camera_index++;
			}
		}

		//Init any script
		component.initialize(m_scheduler, component.getScript());
	}

	// Make sure all viewports have cameras
	for (auto &camera : m_cameras) {
		if (!camera)
			camera = &m_defaultCamera;
	}

	// Warn if scripts are unset for Physics character components
	for (PWorld::PObjectIteratorOfType<PPhysicsCharacterControllerComponent> it(m_world); it; ++it) {
		if (it->getScript() == NULL)
			PHYRE_WARN("Physics character controller component is missing a script. This component will not be updated. A default script 'DefaultCharacterController.lua' is available in the Media\\Scripts\\ directory.\n");
	}

	// Init world renderer
	{PWorldRendererInit init(getWidth(), getHeight());
	init.enableFeature(PE_WORLD_RENDERER_SUPPORT_SHADOWS); // To enable shadow rendering
	init.enableFeature(PWorldRendering::PE_WORLD_RENDERER_SUPPORT_VR);
	init.m_shadowMapCount = GameApplication::c_shadowMapMaxCount;
	init.m_shadowMaps = m_shadowMaps;

	m_worldRendererView.initialize(init);}

	// Add cluster's physics model to physics world.
	if (m_physicsWorld)
		PHYRE_TRY(m_physicsWorld->addPhysicsModelsToWorld(*m_currentLevelCluster));

	// Add the render callback to help debug the scene physics
#ifndef PHYRE_PLATFORM_ORBIS
	static PWorldRendererPassCallback physicsDebugRender(physicsDebugRender, this);
	m_worldRenderer.addCallbacksToPass(PE_PASS_TRANSPARENT, NULL, &physicsDebugRender);
#endif

#ifdef PHYRE_ENABLE_AUDIO	

	PResult result = PE_RESULT_NO_ERROR;

	PAudio::PAudioInterface &audio = PAudio::PAudioInterface::GetInstance();

	// Set the initial listener position, update position in the animate function
	// if needed. Default is relative to cameras.
	//Vectormath::Aos::Vector3 listenerPos(0.0f, 0.0f, 0.0f);
	//audio.setListener3DAttributes(&listenerPos);

	// Find the audio banks in the audio cluster.
	PSharray<PAssetReference *> audioBanks;
	PAssetReference::Find(audioBanks, NULL, NULL, &PHYRE_CLASS(PAudio::PAudioBank));

	for (PUInt32 i = 0; i<audioBanks.getCount(); i++)
	{
		PAudio::PAudioBank &audioBank = (PAudio::PAudioBank &)audioBanks[i]->getAsset();

		if (audioBank.getName() == "EventBank")
			m_eventBank = &audioBank;

		if (audioBank.getName() == "StreamBank")
			m_musicBank = &audioBank;
	}

	// Check if audio event bank (sound effects) has loaded.
	if (m_eventBank)
	{
		result = m_eventBank->registerBank();
		if (result != PE_RESULT_NO_ERROR)
			PHYRE_WARN("Error %d registering event bank\n", result);

	}
	else
	{
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "Unable to find event bank in audio cluster");
	}

	// Check if audio music bank has loaded.
	if (m_musicBank)
	{
		result = m_musicBank->registerBank();
		if (result != PE_RESULT_NO_ERROR)
			PHYRE_WARN("Error %d registering music bank\n", result);

	}
	else
	{
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "Unable to find music bank in audio cluster");
	}

	// Create music/sounds here ready to played.
	// MUSIC
	result = m_musicBank->createEventByName("Music/GameMenu", m_music1);
	result = m_music1.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating game menu music\n", result);
	}

	result = m_musicBank->createEventByName("Music/SpaceBattle", m_music2);
	result = m_music2.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating space battle music\n", result);
	}

	result = m_musicBank->createEventByName("Music/GameOver", m_music3);
	result = m_music3.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating game over music\n", result);
	}

	// SOUND EFFECTS
	// Loops
	result = m_eventBank->createEventByName("EventLoop/Clock Tick Tock", m_clock);
	result = m_clock.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating clock audio event\n", result);
	}

	result = m_eventBank->createEventByName("EventLoop/Move Character", m_move);
	result = m_move.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating 'move character' audio event\n", result);
	}

	// One Shots
	result = m_eventBank->createEventByName("EventOnce/Bounce", m_bounce);
	result = m_bounce.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating bounce audio event\n", result);
	}

	result = m_eventBank->createEventByName("EventOnce/Thud", m_thud);
	result = m_thud.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating thud audio event\n", result);
	}

	result = m_eventBank->createEventByName("EventOnce/Spawn", m_spawn);
	result = m_spawn.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating spawn audio event\n", result);
	}

	result = m_eventBank->createEventByName("EventOnce/Powerup", m_powerup);
	result = m_powerup.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating powerup audio event\n", result);
	}

	result = m_eventBank->createEventByName("EventOnce/Splat", m_splat);
	result = m_splat.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating splat audio event\n", result);
	}

	result = m_eventBank->createEventByName("EventOnce/AI Freeze", m_ai);
	result = m_ai.setVolume(m_volumeMultiplier * m_Volume);
	if (result != PE_RESULT_NO_ERROR)
	{
		PHYRE_WARN("Error %d creating ai freeze audio event\n", result);
	}

#endif //! PHYRE_ENABLE_AUDIO
	return PApplication::initScene();
}

// Description: 
// Exit the scene in preparation for exiting the application.
// Return Value List:
// Other - The scene exit failed.
// PE_RESULT_NO_ERROR - The scene exit succeeded.
PResult GameApplication::exitScene()
{
	// Uninit all scriptable component
	for (PWorld::PObjectIteratorOfType<PScriptableComponent> component(m_world); component; ++component) {
		component->uninitialize();
	}

	// Stop Spawner
	Phyre::PGameplay::PSpawner::Clear();
	Phyre::PGameplay::PSpawner::UnregisterAllMaterials();

	// Clear the input map
	getInputMapper().terminate();
	m_inputMap.clear();
	m_inputMapCluster.clear();

	// Free up the scene context containing the lights
	m_sceneContext.m_lights.resize(0);
	// Free up the scene lights
	m_pointLights.resize(0);
	// Free Shadows
	m_shadowCluster.clear();

	// Free the text objects and text materials
	for (PUInt32 i = 0; i < m_textList.getCount(); i++)
	{
		delete m_textList.getArray()[i];
		m_textList.getArray()[i] = NULL;
		delete m_textMaterials.getArray()[i];
		m_textMaterials.getArray()[i] = NULL;
	}
	PHYRE_TRY(m_textList.resize(0));
	PHYRE_TRY(m_textMaterials.resize(0));

	// Free up spawn & target locators //hhy
	m_enemyAILocators.resize(0);
	m_targetLocators.resize(0);
	m_playerLocators.resize(0);
	m_playerStartLocators.resize(0);
	m_pickUpLocators.resize(0);

#ifdef PHYRE_ENABLE_AUDIO	
	// Stop all events.
	PAudio::PAudioInterface &audio = PAudio::PAudioInterface::GetInstance();
	audio.stopAllEvents();

	// Release the audio events. (test sounds atm, need to find some better wav files).
	m_bounce.release();
	m_move.release();
	m_splat.release();
	m_powerup.release();
	m_clock.release();
	m_spawn.release();
	m_thud.release();
	m_ai.release();
	m_music1.release();
	m_music2.release();
	m_music3.release();
#endif //! PHYRE_ENABLE_AUDIO

	return PApplication::exitScene();
}

// Description:
// Render method.
// Return Value list:
// PE_RESULT_NO_ERROR - The render operation completed successfully.
// Other - An error occurred whilst rendering the scene.
PResult GameApplication::render()
{
	// TODO
	// Update position for dynamic object here

	// Prepare for viewport switch
	PUInt32 viewportCount = m_playerStartCount;
	if (!m_renderViewports)
		viewportCount = 1;

	// Render viewports
	for (PUInt32 i = 0; i < viewportCount; i++) {
		if (!m_renderViewports)
			m_cameras[i]->setAspect((float)(getWidth()) / (float)(getHeight()));
		else
			m_cameras[i]->setAspect((float)(m_viewportConfigs[i].m_width) / (float)(m_viewportConfigs[i].m_height));

		m_cameras[i]->updateViewMatrices();
		m_renderer.setCamera(*m_cameras[i]);

		if (m_renderViewports)
			PHYRE_TRY(m_renderer.setViewport(m_viewportConfigs[i].m_xOffset, m_viewportConfigs[i].m_yOffset, m_viewportConfigs[i].m_width, m_viewportConfigs[i].m_height));

		PHYRE_TRY(m_renderer.setClearColor(0.40f, 0.45f, 0.5f, 1.0f));

		// Main render frame
		PWorldRendering::PWorldRendererFrame wrFrame(m_worldRendererView, *m_cameras[i], m_renderer, m_rendererGroup, m_sceneContext, (float)m_elapsedTime);
		if (m_characterControllers[i]) {
			Vector3 characterPosition = m_characterControllers[i]->getCurrentPosition();
			wrFrame.setOccluderTarget(characterPosition);
		}
		wrFrame.m_clearColor = Vector4(0.40f, 0.45f, 0.5f, 1.0f);
		wrFrame.startFrame(m_world);
		m_worldRenderer.renderWorld(wrFrame, m_world);

		// The navigation debug rendering renders 2 main features. // hhy
		// 1) The navigation mesh overlaying the world geometry.
		// 2) The path for each of the agents, red for floaters and green for bots.
		// 3) The grid patrolled by the floaters (cyan).
		// Since the PNavigationCrowdAgentComponent doesn't store the currently planned path, we use a PPathPlanner to generate a possible path.
		if (m_navigationDebug)
		{
			PCamera &camera = *m_cameras[i];

			// We need to flush and sync the renderer to ensure that these render interface operations occur after the scene rendering has completed.
			PHYRE_TRY(m_renderer.flushRender());
			PHYRE_TRY(m_renderer.syncRender());

			PRenderInterfaceLock lock;
			PRenderInterface &renderInterface = lock.getRenderInterface();
			renderInterface.beginScene(PRenderInterfaceBase::PE_CLEAR_DEPTH_BUFFER_BIT);

			m_navMesh->debugDraw(renderInterface, camera);
			dtNavMeshQuery navMeshQuery;
			if (dtStatusSucceed(navMeshQuery.init(m_navMesh->m_navMesh, 2048)))
			{
				PNavigation::PPathPlanner planner(navMeshQuery);
				for (PUInt32 b = 0; b < BOT_COUNT; b++)
				{
					if (m_bots[b].m_navigationComponent->planPath(planner))
						planner.debugRenderPath(renderInterface, camera, Vector4(0.0f, 1.0f, 0.0f, 0.75f));
				}
				for (PUInt32 f = 0; f < FLOATER_COUNT; f++)
				{
					if (m_floaters[f].m_navigationComponent->planPath(planner))
						planner.debugRenderPath(renderInterface, camera, Vector4(1.0f, 0.0f, 0.0f, 0.75f));
				}
			}

			// Render the floater grid
			Vector4 grid[(FLOATER_SQUARE_ROOT + 1) * 2 * 2];
			Vector3 levelSize = m_levelBounds.getMax() - m_levelBounds.getMin();
			levelSize.setY(0.0f);
			float floaterAreaBounds = 1.0f / FLOATER_SQUARE_ROOT;
			Vector4 levelSizeX = Vector4(mulPerElem(levelSize, Vector3::xAxis()));
			Vector4 levelSizeZ = Vector4(mulPerElem(levelSize, Vector3::zAxis()));
			Vector4 floaterAreaX = levelSizeX * floaterAreaBounds;
			Vector4 floaterAreaZ = levelSizeZ * floaterAreaBounds;

			Vector4 top = Vector4(m_levelBounds.getMin(), 1.0f);
			Vector4 left = top;
			Vector4 *gridPoint = grid;
			for (PUInt32 f = 0; f <= FLOATER_SQUARE_ROOT; f++, top += floaterAreaX, left += floaterAreaZ)
			{
				*gridPoint++ = top;
				*gridPoint++ = top + levelSizeZ;
				*gridPoint++ = left;
				*gridPoint++ = left + levelSizeX;
			}
			renderInterface.debugDraw(PGeometry::PE_PRIMITIVE_LINES, grid, Vector4(0.0f, 1.0f, 1.0f, 0.5f), NULL, PHYRE_STATIC_ARRAY_SIZE(grid), &camera.getViewProjectionMatrix());
			renderInterface.endScene();
		}
	}

	if (m_renderViewports)
		PHYRE_TRY(m_renderer.setViewport(0, 0, (PUInt32)getWidth(), (PUInt32)getHeight()));

	// Render sample gui.
	PImGui::RenderGui(m_renderer, *this);

	return PE_RESULT_NO_ERROR;
}

// Description:
// Informs the application that the window has been resized.
// Return Value List:
// PE_RESULT_NO_ERROR - The application resized successfully.
// Other - The application did not resize successfully.
PResult GameApplication::resize()
{
	configureViewports();
	return PApplication::resize();
}

// Description:
// Handle user inputs.
// Return Value List:
// PE_RESULT_NO_ERROR - The inputs were handled successfully.
// Other - An error occurred whilst handling inputs. 
PResult GameApplication::handleInputs()
{
	PHYRE_TRY(m_physicsWorld->syncSimulation());

	if (checkAndClearKey(PInputBase::InputChannel_Key_1))
		m_showImGui = !m_showImGui;
	if (checkAndClearKey(PInputBase::InputChannel_Key_2))
		m_navigationDebug = !m_navigationDebug;
	if (checkAndClearKey(PInputBase::InputChannel_Key_3))
		m_physicsDebug = !m_physicsDebug;
	if (checkAndClearKey(PInputBase::InputChannel_Key_4))
		m_renderViewports = !m_renderViewports;

#ifdef PHYRE_ENABLE_AUDIO
	// Pause / Play music.
	if (checkAndClearKey(PInputBase::InputChannel_Key_B) || checkAndClearJoypadButton(PInput::InputChannel_Button_L3))
	{
		if (m_music1Playing)
		{
			PHYRE_PRINTF("Pausing music1\n");
			m_music1.pause();
			m_music1Playing = false;
		}
		else if (!m_music2Playing && !m_music3Playing)
		{
			if (m_music1Started)
			{
				m_music1.resume();
				PHYRE_PRINTF("Resuming music1\n");
			}
			else
			{
				m_music1.play();
				PHYRE_PRINTF("Playing music1\n");
			}

			m_music1Playing = true;
			m_music1Started = true;
		}
	}

	if (checkAndClearKey(PInputBase::InputChannel_Key_N) || checkAndClearJoypadButton(PInput::InputChannel_Button_R3))
	{
		if (m_music2Playing)
		{
			PHYRE_PRINTF("Pausing music2\n");
			m_music2.pause();
			m_music2Playing = false;
		}
		else if (!m_music1Playing && !m_music3Playing)
		{
			if (m_music2Started)
			{
				m_music2.resume();
				PHYRE_PRINTF("Resuming music2\n");
			}
			else
			{
				m_music2.play();
				PHYRE_PRINTF("Playing music2\n");
			}

			m_music2Playing = true;
			m_music2Started = true;
		}
	}

	if (checkAndClearKey(PInputBase::InputChannel_Key_M) || checkAndClearJoypadButton(PInput::InputChannel_Button_Select))
	{
		if (m_music3Playing)
		{
			PHYRE_PRINTF("Pausing music3\n");
			m_music3.pause();
			m_music3Playing = false;
		}
		else if (!m_music1Playing && !m_music2Playing)
		{
			if (m_music3Started)
			{
				m_music3.resume();
				PHYRE_PRINTF("Resuming music3\n");
			}
			else
			{
				m_music3.play();
				PHYRE_PRINTF("Playing music3\n");
			}

			m_music3Playing = true;
			m_music3Started = true;
		}
	}

	// Set music/sound effect volume.
	if (checkAndClearKey(PInputBase::InputChannel_Key_Numpad_Minus) || checkAndClearJoypadButton(PInput::InputChannel_Button_Down))
	{
		float prevVolume = m_Volume;
		m_Volume = PhyreClamp(m_Volume - 0.1f, 0.0f, 1.0f);

		if (prevVolume != m_Volume)
		{
			m_bounce.setVolume(m_volumeMultiplier * m_Volume);
			m_thud.setVolume(m_volumeMultiplier * m_Volume);
			m_move.setVolume(m_volumeMultiplier * m_Volume);
			m_clock.setVolume(m_volumeMultiplier * m_Volume);
			m_spawn.setVolume(m_volumeMultiplier * m_Volume);
			m_powerup.setVolume(m_volumeMultiplier * m_Volume);
			m_splat.setVolume(m_volumeMultiplier * m_Volume);
			m_ai.setVolume(m_volumeMultiplier * m_Volume);
			m_music1.setVolume(m_volumeMultiplier * m_Volume);
			m_music2.setVolume(m_volumeMultiplier * m_Volume);
			m_music3.setVolume(m_volumeMultiplier * m_Volume);
			PHYRE_PRINTF("Volume: %.1f\n", m_Volume);
		}
		else
		{
			PHYRE_PRINTF("Volume already at minimum\n");
		}
	}

	if (checkAndClearKey(PInputBase::InputChannel_Key_Numpad_Plus) || checkAndClearJoypadButton(PInput::InputChannel_Button_Up))
	{
		float prevVolume = m_Volume;
		m_Volume = PhyreClamp(m_Volume + 0.1f, 0.0f, 1.0f);

		if (prevVolume != m_Volume)
		{
			m_bounce.setVolume(m_volumeMultiplier * m_Volume);
			m_thud.setVolume(m_volumeMultiplier * m_Volume);
			m_move.setVolume(m_volumeMultiplier * m_Volume);
			m_clock.setVolume(m_volumeMultiplier * m_Volume);
			m_spawn.setVolume(m_volumeMultiplier * m_Volume);
			m_powerup.setVolume(m_volumeMultiplier * m_Volume);
			m_splat.setVolume(m_volumeMultiplier * m_Volume);
			m_ai.setVolume(m_volumeMultiplier * m_Volume);
			m_music1.setVolume(m_volumeMultiplier * m_Volume);
			m_music2.setVolume(m_volumeMultiplier * m_Volume);
			m_music3.setVolume(m_volumeMultiplier * m_Volume);
			PHYRE_PRINTF("Volume: %.1f \n", m_Volume);
		}
		else
		{
			PHYRE_PRINTF("Volume already at maximum\n");
		}
	}

	// Loop sound effects to accompany music.
	if (checkAndClearKey(PInputBase::InputChannel_Key_1))
	{
		if (m_clockPlaying)
		{
			PHYRE_PRINTF("Pausing clock\n");
			m_clock.pause();
			m_clockPlaying = false;
		}
		else
		{
			if (m_clockStarted)
			{
				m_clock.resume();
				PHYRE_PRINTF("Resuming clock\n");
			}
			else
			{
				m_clock.play();
				PHYRE_PRINTF("Playing clock\n");
			}

			m_clockPlaying = true;
			m_clockStarted = true;
		}
	}

	if (checkAndClearKey(PInputBase::InputChannel_Key_2))
	{
		if (m_movePlaying)
		{
			PHYRE_PRINTF("Pausing movement\n");
			m_move.pause();
			m_movePlaying = false;
		}
		else
		{
			if (m_moveStarted)
			{
				m_move.resume();
				PHYRE_PRINTF("Resuming movement\n");
			}
			else
			{
				m_move.play();
				PHYRE_PRINTF("Playing movement\n");
			}

			m_movePlaying = true;
			m_moveStarted = true;
		}
	}

	// One shot sound effects
	if (checkAndClearKey(PInputBase::InputChannel_Key_3))
	{
		if (!m_bounce.isPlaying())
		{
			m_bounce.play();
		}
	}

	if (checkAndClearKey(PInputBase::InputChannel_Key_4))
	{
		if (!m_thud.isPlaying())
		{
			m_thud.play();
		}
	}

	if (checkAndClearKey(PInputBase::InputChannel_Key_5))
	{
		if (!m_spawn.isPlaying())
		{
			m_spawn.play();
		}
	}

	if (checkAndClearKey(PInputBase::InputChannel_Key_6))
	{
		if (!m_powerup.isPlaying())
		{
			m_powerup.play();
		}
	}

	if (checkAndClearKey(PInputBase::InputChannel_Key_7))
	{
		if (!m_splat.isPlaying())
		{
			m_splat.play();
		}
	}

	if (checkAndClearKey(PInputBase::InputChannel_Key_8))
	{
		if (!m_ai.isPlaying())
		{
			m_ai.play();
		}
	}
#endif //! PHYRE_ENABLE_AUDIO

	return PApplication::handleInputs();
}

// Handle Animation
PResult GameApplication::animate()
{
	PHYRE_TRY(m_physicsWorld->syncSimulation());

	// Navigation updates //hhy
	{static bool s_completedFirstFrame;
	// Skip the first frame to avoid large startup times
	if (s_completedFirstFrame)
	{
		// To update PNavigationPathFollowingComponent you need to provide a path planner that can be used to plan the path for the agent
		dtNavMeshQuery navMeshQuery;
		if (dtStatusSucceed(navMeshQuery.init(m_navMesh->m_navMesh, 2048)))
		{
			PNavigation::PPathPlanner planner(navMeshQuery);
			for (PCluster::PObjectIteratorOfType<PNavigation::PNavigationPathFollowingComponent> it(*m_currentLevelCluster); it; ++it)
				it->moveToTarget(planner, m_elapsedTime);
		}

		// To update PNavigationCrowdAgentComponents you need to ensure that their crowd has been updated then use the updateFromCrowd() method to extract their current state
		PHYRE_TRY(PNavigation::PUtilityNavigation::UpdateCrowd(m_elapsedTime, NULL));
		for (PCluster::PObjectIteratorOfType<PNavigation::PNavigationCrowdAgentComponent> it(*m_currentLevelCluster); it; ++it)
			it->updateFromCrowd();

		for (PUInt32 b = 0; b < BOT_COUNT; b++)
		{
			Bot &bot = m_bots[b];
			//Player &player = m_players[b];
			PWorldMatrix *worldMatrix = bot.m_worldMatrix;
			//PWorldMatrix *worldMatrix1 = player.m_worldMatrix;
			if (!worldMatrix)
				continue;

			PNavigation::PNavigationTargetComponent *navigationTarget = bot.m_navigationTarget;
			if (navigationTarget)
				navigationTarget->update(navMeshQuery, worldMatrix->getMatrix().getTranslation());

			// If the bot gets close to their target, move them to a new target
			PNavigation::PNavigationCrowdAgentComponent *navigationComponent = bot.m_navigationComponent;
			if (!navigationComponent)
				continue;

			if (navigationComponent->getDistanceToTarget() < 1.0f)
			{
				const PNavigation::PNavigationTargetComponent *nextTarget = NULL;
				const PNavigation::PNavigationTargetComponent *currentTarget = navigationComponent->getTarget();
				do
				{
					nextTarget = &m_targets[m_nextTargetID++ % m_targetLocators.getCount()];
				} while (nextTarget == currentTarget);
				navigationComponent->setTarget(nextTarget);
			}
		}

		// If the target for a floater is no longer in its area, choose a new target
		for (PUInt32 f = 0; f < FLOATER_COUNT; f++)
		{
			Floater &floater = m_floaters[f];
			if (!floater.targetNeedsUpdate())
				continue;

			PNavigation::PNavigationTargetComponent *selectedTarget = &m_targets[f];

			for (PUInt32 b = 0; b < BOT_COUNT; b++)
			{
				PNavigation::PNavigationTargetComponent *navigationTarget = m_bots[b].m_navigationTarget;
				if (!floater.containsTarget(*navigationTarget))
					continue;
				floater.m_navigationComponent->setTarget(navigationTarget);
				selectedTarget = navigationTarget;
				break;
			}
			// Update for moving target
			for (PUInt32 player = 0; player < m_playerStartCount; player++)
			{
				PNavigation::PNavigationTargetComponent *navigationTarget = &m_moving_targets[player];
				if (navigationTarget)
					navigationTarget->update(navMeshQuery, m_playerLocators[player]->getLocalToWorldMatrix()->getMatrix().getTranslation());

				if (!floater.containsTarget(*navigationTarget))
				{
					continue;
				}
				floater.m_navigationComponent->setTarget(navigationTarget);
				selectedTarget = navigationTarget;
				break;
			}
			floater.m_navigationComponent->setTarget(selectedTarget);
		}
	}
	s_completedFirstFrame = true;
	}

	// Clamp frame time to avoid too large physics simulation jumps
	float timeDiff = PhyreMinOfPair(static_cast<float>(m_elapsedTime), 1.0f / 10.0f);
	m_physicsWorld->updateWorldMatrices();
	m_physicsWorld->stepSimulation(timeDiff);

	PHYRE_TRY(PApplication::defaultAnimate((float)timeDiff));

	return PApplication::animate();
}

// Description:
// Forward rendering
void GameApplication::pickNearestLights(const Vectormath::Aos::Vector3 &position) {
	PUInt32 newLightsSize = 0;
	const PUInt32 c_maxLights = 3;

	// Directional light
	const PUInt32 maxLights = c_maxLights - 1;
	const PRendering::PLight *newLights[c_maxLights];
	float distances[c_maxLights];
	if (m_lightCount == 0)
	{
		m_sceneContext.m_lights.resize(PARRAY_ALLOCSITE 0);
		return;
	}

	// Point lights
	// Sort list so it only contains the lights closest to the mesh instance
	for (PUInt32 i = 0; i < m_lightCount; i++)
	{
		Vectormath::Aos::Vector3 lightPos = m_pointLights[i]->getLocalToWorldMatrix()->getMatrix().getTranslation();
		Vectormath::Aos::Vector3 diff = lightPos - position;
		float magnitudeSqr = Vectormath::Aos::lengthSqr(diff);
		// Fill any empty cells in the array
		if (newLightsSize < maxLights)
		{
			newLights[newLightsSize] = m_pointLights[i];
			distances[newLightsSize] = magnitudeSqr;
			newLightsSize++;
		}
		else
		{
			float farthestDistance = 0;
			int farthestDistIndex = -1;
			for (PUInt32 j = 0; j < maxLights; j++)
			{
				// If this light is closer to the model than any
				// other light in the list then find the farthest
				// light in the list and replace it
				if (distances[j] > magnitudeSqr
					&& distances[j] > farthestDistance)
				{
					farthestDistIndex = j;
					farthestDistance = distances[j];
				}
			}
			if (farthestDistIndex != -1)
			{
				newLights[farthestDistIndex] = m_pointLights[i];
				distances[farthestDistIndex] = magnitudeSqr;
			}
		}
	}

	// Set up the scene context with the newly found lights
	m_sceneContext.m_lights.resize(PARRAY_ALLOCSITE newLightsSize);
	const PRendering::PLight **light = m_sceneContext.m_lights.getArray();
	PUInt32 lightNum = 0;
	for (lightNum = 0; lightNum < newLightsSize; lightNum++)
		*light++ = newLights[lightNum];

	// After the program finishes finding the nearest lights, you then add in the directional light before the scene context light array is changed.
	newLights[c_maxLights - 1] = m_directionalLight;
	newLightsSize++;
}

// Description:
// Configures the viewports for the scene.
void GameApplication::configureViewports() {

	PUInt32 halfWidth = (PUInt32)ceilf(getWidth() / 2.0f);
	PUInt32 halfHeight = (PUInt32)ceilf(getHeight() / 2.0f);
	PUInt32 aThirdHeight = (PUInt32)ceilf(getHeight() / 3.0f);
	PUInt32 twoThirdsHeight = getHeight() - aThirdHeight;
	PUInt32 aThirdWidth = (PUInt32)ceilf(getWidth() / 3.0f);
	PUInt32 twoThirdsWidth = getWidth() - aThirdWidth;

	switch (m_playerStartCount) {
	case 1: { // 1 camera
		m_viewportConfigs[0].configure(0, 0, getWidth(), getHeight());
		break;
	}
	case 2: { // 1 overview camera, 1 player camera side by side
		m_viewportConfigs[0].configure(0, 0, halfWidth, getHeight());
		m_viewportConfigs[1].configure(halfWidth, 0, halfWidth, getHeight());
		break;
	}
	case 3: { // 1 overview camera, 2 player cameras side by side
		m_viewportConfigs[0].configure(0, 0, aThirdWidth, getHeight());
		m_viewportConfigs[1].configure(aThirdWidth, 0, aThirdWidth, getHeight());
		m_viewportConfigs[2].configure(twoThirdsWidth, 0, aThirdWidth, getHeight());
		break;
	}
	case 4: { // 1 overview camera, 3 player camera checkered
		m_viewportConfigs[0].configure(0, halfHeight, halfWidth, halfHeight);
		m_viewportConfigs[1].configure(halfWidth, halfHeight, halfWidth, halfHeight);
		m_viewportConfigs[2].configure(0, 0, halfWidth, halfHeight);
		m_viewportConfigs[3].configure(halfWidth, 0, halfWidth, halfHeight);
		break;
	}
	default: {
		m_viewportConfigs[0].configure(0, 0, getWidth(), getHeight());
		break;
	}
	}
}

// Description:
// Init inputmap
void GameApplication::initInputMap()
{
	// Create and add default mappings to the input mapper.

	// Character 1
	{// Keyboard mappings
		PInputSourceKey keyAxis0(PHYRE_GET_INPUT_KEY_TYPE(Key_W), PHYRE_GET_INPUT_KEY_TYPE(Key_S));// Forward
		PInputSourceKey keyAxis1(PHYRE_GET_INPUT_KEY_TYPE(Key_D), PHYRE_GET_INPUT_KEY_TYPE(Key_A));// Turn
		PInputSourceKey keyButton0(PHYRE_GET_INPUT_KEY_TYPE(Key_X));										// Jump
		PInputSourceKey keyButton1(PHYRE_GET_INPUT_KEY_TYPE(Key_Space));									// Reset
		PInputSourceKey keyButton2(PHYRE_GET_INPUT_KEY_TYPE(Key_V));										// Toggle Viewport
		PInputSourceKey keyButton3(PHYRE_GET_INPUT_KEY_TYPE(Key_C));										// Toggle Camera Mode

																											// Joystick mappings
		PInputSourceJoypadAxis joyLeftStickY(PHYRE_GET_INPUT_AXIS_TYPE(YAxis_0));
		PInputSourceJoypadAxis joyLeftStickX(PHYRE_GET_INPUT_AXIS_TYPE(XAxis_0));
		PInputSourceJoypadButton joyCross(PHYRE_GET_INPUT_JOYPAD_BUTTON_TYPE(Button_Cross));
		PInputSourceJoypadButton joySquare(PHYRE_GET_INPUT_JOYPAD_BUTTON_TYPE(Button_Square));
		PInputSourceJoypadButton joyCircle(PHYRE_GET_INPUT_JOYPAD_BUTTON_TYPE(Button_Circle));
		PInputSourceJoypadButton joyTriangle(PHYRE_GET_INPUT_JOYPAD_BUTTON_TYPE(Button_Triangle));

		// Add the input mappings
		m_inputMap.setCluster(m_inputMapCluster);

		// keyboard
		m_inputMap.addInput("FORWARD1", keyAxis0);
		m_inputMap.addInput("RIGHT1", keyAxis1);
		m_inputMap.addInput("JUMP1", keyButton0);
		m_inputMap.addInput("RESET1", keyButton1);
		m_inputMap.addInput("SWITCH_VIEWPORT1", keyButton2);
		m_inputMap.addInput("SWITCH_CAMERA1", keyButton3);

		// joypad
		m_inputMap.addInput("FORWARD1", joyLeftStickY);
		m_inputMap.addInput("RIGHT1", joyLeftStickX);
		m_inputMap.addInput("JUMP1", joyCross);
		m_inputMap.addInput("RESET1", joyCircle);
		m_inputMap.addInput("SWITCH_VIEWPORT1", joyTriangle);
		m_inputMap.addInput("SWITCH_CAMERA1", joySquare);}

	// Character 2
	{// Keyboard mappings
		PInputSourceKey keyAxis0(PHYRE_GET_INPUT_KEY_TYPE(Key_Up), PHYRE_GET_INPUT_KEY_TYPE(Key_Down));	// Forward
		PInputSourceKey keyAxis1(PHYRE_GET_INPUT_KEY_TYPE(Key_Right), PHYRE_GET_INPUT_KEY_TYPE(Key_Left));	// Turn
		PInputSourceKey keyButton0(PHYRE_GET_INPUT_KEY_TYPE(Key_J));							   // Jump
		PInputSourceKey keyButton1(PHYRE_GET_INPUT_KEY_TYPE(Key_Space));						   // Reset
		PInputSourceKey keyButton2(PHYRE_GET_INPUT_KEY_TYPE(Key_V));							   // Toggle Viewport
		PInputSourceKey keyButton3(PHYRE_GET_INPUT_KEY_TYPE(Key_C));							   // Toggle Camera Mode

																								   // Joystick mappings
		PInputSourceJoypadAxis joyLeftStickY(PHYRE_GET_INPUT_AXIS_TYPE(YAxis_0), 1);
		PInputSourceJoypadAxis joyLeftStickX(PHYRE_GET_INPUT_AXIS_TYPE(XAxis_0), 1);
		PInputSourceJoypadButton joyCross(PHYRE_GET_INPUT_JOYPAD_BUTTON_TYPE(Button_Cross), NULL, 1);
		PInputSourceJoypadButton joySquare(PHYRE_GET_INPUT_JOYPAD_BUTTON_TYPE(Button_Square), NULL, 1);
		PInputSourceJoypadButton joyCircle(PHYRE_GET_INPUT_JOYPAD_BUTTON_TYPE(Button_Circle), NULL, 1);
		PInputSourceJoypadButton joyTriangle(PHYRE_GET_INPUT_JOYPAD_BUTTON_TYPE(Button_Triangle), NULL, 1);

		// keyboard
		m_inputMap.addInput("FORWARD2", keyAxis0);
		m_inputMap.addInput("RIGHT2", keyAxis1);
		m_inputMap.addInput("JUMP2", keyButton0);
		m_inputMap.addInput("RESET2", keyButton1);
		m_inputMap.addInput("SWITCH_VIEWPORT2", keyButton2);
		m_inputMap.addInput("SWITCH_CAMERA2", keyButton3);

		// joypad
		m_inputMap.addInput("FORWARD2", joyLeftStickY);
		m_inputMap.addInput("RIGHT2", joyLeftStickX);
		m_inputMap.addInput("JUMP2", joyCross);
		m_inputMap.addInput("RESET2", joyCircle);
		m_inputMap.addInput("SWITCH_VIEWPORT2", joyTriangle);
		m_inputMap.addInput("SWITCH_CAMERA2", joySquare);}

	getInputMapper().setInputMap(&m_inputMap);
}

// Description:
// A world renderer callback to render the physics debug information if required.
// Arguments:
// frame - Information about the current frame being rendered.
// callbackData - The PPhysicsSample specified when the callback was registered.
// Return Value List:
// PE_RESULT_NO_ERROR - The callback was successful.
// Other - An error occurred.
PResult GameApplication::physicsDebugRender(PWorldRendererFrame &frame, void *callbackData)
{
	GameApplication *app = static_cast<GameApplication*>(callbackData);

	if (app->m_physicsDebug)
	{
		PRenderer &renderer = frame.m_renderer;
		PHYRE_TRY(renderer.clearScene(PRenderInterfaceBase::PE_CLEAR_DEPTH_BUFFER_BIT));

		// We need to flush and sync the renderer to ensure that these render interface operations occur after the scene rendering has completed.
		PHYRE_TRY(renderer.flushRender());
		PHYRE_TRY(renderer.syncRender());

		// Render the debug information depending on the physics platform
#ifdef PHYRE_PHYSICS_PLATFORM_BULLET
		PPhysics::PPhysicsWorldBullet &bulletWorld = *app->m_physicsWorld;
		bulletWorld.renderPhysicsDebug(frame.m_camera);
#endif //! PHYRE_PHYSICS_PLATFORM_BULLET

#ifdef PHYRE_PHYSICS_PLATFORM_PFX
		PPhysics::PPhysicsWorldPfx &pfxWorld = *physicsSample->m_physicsWorld;
		pfxWorld.renderPhysicsDebug(frame.m_camera);
#endif //! PHYRE_PHYSICS_PLATFORM_PFX
	}

	return PE_RESULT_NO_ERROR;
}

// Description:
// Setup call for the sample gui.
// Return Value List:
// Other -  The setup failed.
// PE_RESULT_NO_ERROR - The setup succeeded.
PResult GameApplication::setupGui()
{
	ImGui::Checkbox("Debug Navigation", &m_navigationDebug);
	ImGui::Checkbox("Debug Physics", &m_physicsDebug);
	ImGui::Checkbox("Viewport render", &m_renderViewports);
	ImGui::Text("Framerate = %f fps, %f ms\n", m_fps, 1000.0f / m_fps);

	return PApplication::setupGui();
}

// Description:
// Gathers all of the locators with a specified name from a cluster. 
// Arguments:
// cluster : The cluster to find locators in.
// locators : An array for the gathered locators.
// name : The name of the locators to find.
// Return Value List:
// PE_RESULT_NULL_POINTER_ARGUMENT : The name was NULL.
// PE_RESULT_NO_ERROR : The locators were gathered successfully.
// Other : Unable to allocate sufficient storage for the locators.
PResult GameApplication::gatherLocators(PCluster &cluster, PSharray<PGameplay::PLocator *> &locators, const PChar *name)
{
	if (!name)
		return PE_RESULT_NULL_POINTER_ARGUMENT;

	PUInt32 count = 0;
	for (PCluster::PConstObjectIteratorOfType<PGameplay::PLocator> it(cluster); it; ++it)
	{
		const PChar *locatorName = it->getName();
		if (!locatorName)
			continue;
		if (!strcmp(locatorName, name))
			count++;
	}
	PHYRE_TRY(locators.resize(PARRAY_ALLOCSITE count));

	PGameplay::PLocator **locator = locators.getArray();
	for (PCluster::PObjectIteratorOfType<PGameplay::PLocator> it(cluster); it; ++it)
	{
		PGameplay::PLocator &currentLocator = *it;
		const PChar *locatorName = currentLocator.getName();
		if (!locatorName)
			continue;
		if (!strcmp(locatorName, name))
			*locator++ = &currentLocator;
	}
	PHYRE_ASSERT(locator == locators.getArray() + count);
	return PE_RESULT_NO_ERROR;
}

// Description:
// Iterates an array of locators and moves them so that they are on the surface of a navigation mesh.
// Optionally also copies the locations to an array of PNavigationTargetComponent objects.
// Arguments:
// cluster : The cluster containing the locators so that their nodes can be updated.
// navMesh : The navigation mesh to attach locators to.
// locators : The locators to attach.
// targets : An optional array of targets to be copied from the locators.
// Return Value List:
// PE_RESULT_INVALID_ARGUMENT : The specified navMesh has no Detour representation.
// PE_RESULT_UNKNOWN_ERROR : An error occurred while initializing a navmesh query.
// PE_RESULT_NULL_POINTER_ARGUMENT : One of the locator pointers was NULL.
// PE_RESULT_NO_ERROR : The locators were attached successfully.
PResult GameApplication::attachLocatorsToNavMesh(PCluster &cluster, const PNavigation::PNavMesh &navMesh, PSharray<PGameplay::PLocator *> &locators, PNavigation::PNavigationTargetComponent *targets)
{
	dtNavMesh *detourNavMesh = navMesh.m_navMesh;
	if (!detourNavMesh)
		return PE_RESULT_INVALID_ARGUMENT;
	PUInt32				count = locators.getCount();
	PGameplay::PLocator	**locatorArray = locators.getArray();
	dtNavMeshQuery		query;
	if (!dtStatusSucceed(query.init(detourNavMesh, 1)))
		return PE_RESULT_UNKNOWN_ERROR;

	for (PUInt32 i = 0; i < count; i++)
	{
		PGameplay::PLocator *locator = *locatorArray++;
		if (!locator)
			return PE_RESULT_NULL_POINTER_ARGUMENT;
		PWorldMatrix *locatorWorldMatrix = locator->getLocalToWorldMatrix();
		PMatrix4x3 &m = locatorWorldMatrix->getMatrix();
		Vector3 origin = m.getTranslation();
		PNavigation::PNavigationTargetComponent locatorOnNavMesh;
		PNavigation::PNavigationTargetComponent &target = targets ? *targets++ : locatorOnNavMesh;
		target.update(query, origin);
		m.setTranslation(target.getPosition());

		// Propagate the change to the node in the scene for the locator
		PScene::PNode *locatorNode = PScene::PNode::FindNodeWithWorldMatrix(cluster, locatorWorldMatrix);
		if (locatorNode)
			locatorNode->setMatricesForWorldMatrix(PMatrix4(m));
	}
	return PE_RESULT_NO_ERROR;
}

// Description:
// Creates a new mesh instance based on an existing mesh instance.
// Arguments:
// cluster : The cluster in which to allocate objects.
// sourceInstance : The source mesh instance to share the mesh of and copy the bounds from.
// worldMatrix : The world matrix for the mesh instance
// preallocatedIL : A preallocated mesh instance instance list to allow grouping of mesh instances to optimize rendering.
// Return Value List:
// PE_RESULT_OUT_OF_MEMORY : The specified navMesh has no Detour representation.
// PE_RESULT_NO_ERROR : The locators were attached successfully.
// Note:
// This sample only creates the minimum to create a new instance of a static mesh
PResult GameApplication::cloneMeshInstanceSimple(PCluster &cluster, const PRendering::PMeshInstance &sourceInstance, PWorldMatrix &worldMatrix, PInstanceList &preallocatedIL)
{
	PGeometry::PMesh	&mesh = sourceInstance.getMesh();
	PMeshInstance		*instance = preallocatedIL.allocateAndConstructObjectFromFreeList<PMeshInstance>(mesh);
	if (!instance)
		return PE_RESULT_OUT_OF_MEMORY;
	instance->setLocalToWorldMatrix(&worldMatrix);

	const PMeshInstanceBounds *bounds = sourceInstance.getBounds();
	if (bounds)
	{
		PMeshInstanceBounds *newBotBounds = cluster.create<PMeshInstanceBounds>(1);
		if (!newBotBounds)
			return PE_RESULT_OUT_OF_MEMORY;
		newBotBounds->setMinAndSize(bounds->getMin(), bounds->getSize());
		newBotBounds->setWorldMatrix(&worldMatrix);
		newBotBounds->setMeshInstance(instance);

	}
	return PE_RESULT_NO_ERROR;
}

//
PResult GameApplication::DrawAllText()
{
	// Render Text
	PHYRE_TRY(m_renderer.beginScene(PRenderInterfaceBase::PE_CLEAR_DEPTH_BUFFER_BIT));
	// Render the text objects
	for (PUInt32 i = 0; i < m_textHelper.getTexts().getCount(); i++)
	{
		if (m_textHelper.getTexts().getArray()[i])
			PHYRE_TRY(m_textHelper.getTexts().getArray()[i]->renderText(m_renderer));
	}
	PHYRE_TRY(m_renderer.endScene());

	return PE_RESULT_NO_ERROR;
}

// Description:
// Constructs a default instance of this class in a buffer.
// Arguments:
// buffer - The buffer in which to construct a default instance.
// Return Value List:
// true: A default instance was allocated in the buffer.
// false: A default instance was not allocated in the buffer.
bool GameApplication::ConstructDefaultInstance(void *buffer)
{
	(void)buffer;
	return false;
}

// Spawn Pick ups on Locators
void GameApplication::spawnPickUps() {
	PInt32 pickUpCount = m_pickUpLocators.getCount();
	for (PInt32 i = 0; i < pickUpCount; i++) {
		PEntity* pickup = PSpawner::InstantiateHierarchy(NULL, "PickUp");
		if (pickup) {
			pickup->setWorldMatrix(m_pickUpLocators[i]->getLocalToWorldMatrix());
		}
		PHYRE_PRINTF("Instance count %i\n", PSpawner::GetTotalInstancesCount());
	}
}

//
void GameApplication::onPickupEnter(PEntity * entity)
{
	PNameComponent *nc = entity->getComponentOfType<PNameComponent>();
	PHYRE_PRINTF("%s\n", PString(nc->getName()).c_str());

	Phyre::PSharray<PString> names;
	PSpawner::GetListNames(names);
}

//
void GameApplication::pickupBoost(Phyre::PCharacter::PPhysicsCharacterControllerComponent * controller)
{
	controller->setJumpHeight(3.0f);
	m_physicsWorld->syncSimulation();
	//controller->setVelocity(100);
}

#endif //#ifndef SHOULD_LOAD_SANDBOX_APPLICATION