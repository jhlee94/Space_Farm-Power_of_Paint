#include <../Samples/Common/PhyreSamplesCommon.h>
#include <../Samples/Common/PhyreSamplesCommonScene.h>

#ifdef SHOULD_LOAD_SANDBOX_APPLICATION

#ifndef SANDBOXAPPLICATION_H
#define SANDBOXAPPLICATION_H

//This is your own sandbox application which you can use to test features, learn
//the engine, etc. Please do not check this (and the .cpp) file in to master
//or review branch (though, you should continue to check this in to your
//own personal branch on Git)
//
//A define has been setup in GameConfig.h which controls which application
//will be loaded. Comment out the define to load up the shared game application
//rather than your sandbox

// Description:
// Sample application definition.
class SandboxApplication : public Phyre::PFramework::PApplication
{
	PHYRE_BIND_DECLARE_CLASS_WITHOUT_DEFAULT_CONSTRUCTOR(SandboxApplication, Phyre::PFramework::PApplication);
private:
	// The default camera to use if no camera can be found in the asset file.
	Phyre::PCameraPerspective m_defaultCamera;

	// The cameras used for rendering the scene. This is the camera found in the asset file.
	Phyre::PCameraPerspective *m_cameras[MAX_NUMBER_OF_PLAYER];
	// The pointer to the character controller.
	Phyre::PGameplay::PCameraControllerComponent *m_cameraControllers[MAX_NUMBER_OF_PLAYER];
	// The pointer to the character controller.
	Phyre::PCharacter::PPhysicsCharacterControllerComponent *m_characterControllers[MAX_NUMBER_OF_PLAYER];
	// Default Camera Controller
	Phyre::PWorldMatrixOrbitController	m_cameraController;

	// Game Menu
	Phyre::PCameraOrthographic *m_menu_camera;

	// Lighting
	Phyre::PUInt32 m_lightCount;
	Phyre::PArray<const Phyre::PRendering::PLight *> m_pointLights;
	const Phyre::PRendering::PLight *m_directionalLight;

	// Shadow
	// Description:
	// The constants related to shadow maps.
	enum PShadowMapSize
	{
#ifdef PHYRE_PLATFORM_PSP2        
		c_shadowMapSize = 1024,            // The shadow map size.
#else //! PHYRE_PLATFORM_PSP2
		c_shadowMapSize = 2048,            // The shadow map size.
#endif //! PHYRE_PLATFORM_PSP2
		c_shadowMapMaxCount = 4            // The number of shadow maps allocated.
	};
	Phyre::PRendering::PRenderTarget						  *m_shadowMaps[c_shadowMapMaxCount];    // The shadow map render targets.
	Phyre::PCluster                                           m_shadowCluster;						// The cluster to populate with shadowing objects.

	// Level Cluster
	Phyre::PCluster *m_currentLevelCluster;
	Phyre::PSamplesCommon::PLoadedClusterArray m_loadedLevelClusters;

	// Navigation mesh
	Phyre::PNavigation::PNavMesh *m_navMesh;

	// Input Map
	Phyre::PInputs::PInputMap m_inputMap;
	Phyre::PCluster m_inputMapCluster;

	//Render viewport switch
	bool m_renderViewports;

	//Render Nav debug
	bool m_navigationDebug;

	//Render Physics debug
	bool m_physicsDebug;

	// The array of viewports to render to.
	PViewportConfig	m_viewportConfigs[MAX_NUMBER_OF_PLAYER];

	// Navigation HHY
	Phyre::PRendering::PBoundsAggregator			m_levelBounds;
	// The array of bots in this sample.
	Bot												m_bots[BOT_COUNT];
	// The array of floaters in this sample.
	Floater											m_floaters[FLOATER_COUNT];
	// Floater target
	Target                                          m_target[FLOATER_COUNT];
	// The locators in the level that represent bot spawn positions.
	Phyre::PSharray<Phyre::PGameplay::PLocator *> 	m_enemyAILocators;
	// The locators in the level that represent bot navigation targets.
	Phyre::PSharray<Phyre::PGameplay::PLocator *> 	m_targetLocators;
	// An array of navigation targets allocated for each target locator.
	Phyre::PNavigation::PNavigationTargetComponent	*m_targets;
	// An array of navigation targets allocated for each target locator.
	Phyre::PNavigation::PNavigationTargetComponent	*m_moving_targets;
	// Player locators
	Phyre::PSharray<Phyre::PGameplay::PLocator *>   m_playerLocators;
	// Player Start locators
	Phyre::PSharray<Phyre::PGameplay::PLocator *>   m_playerStartLocators;
	// Pick Ups locators
	Phyre::PSharray<Phyre::PGameplay::PLocator *>   m_pickUpLocators;
	// The ID of the next target to use.
	Phyre::PUInt32									m_nextTargetID;

	Phyre::PInstanceList *botIL;

	// Navigation locators
	Phyre::PUInt32 m_enemyAICount;
	Phyre::PUInt32 m_targetCount;
	Phyre::PUInt32 m_playerCount;

	// Number of Character
	Phyre::PUInt32 m_playerStartCount;

#ifdef PHYRE_ENABLE_AUDIO
	Phyre::PAudio::PAudioBank	*m_eventBank;			// Audio Events Bank - contains the events (sound effects) to call.
	Phyre::PAudio::PAudioBank	*m_musicBank;			// Audio Music Bank - contains the streamed music event(s) to call.

														// As many as we need...
	Phyre::PAudio::PAudioEvent	m_bounce;				// sound effect 1
	Phyre::PAudio::PAudioEvent	m_move;					// sound effect 2
	Phyre::PAudio::PAudioEvent	m_splat;				// sound effect 3
	Phyre::PAudio::PAudioEvent	m_powerup;				// sound effect 4
	Phyre::PAudio::PAudioEvent	m_clock;				// sound effect 5
	Phyre::PAudio::PAudioEvent	m_turn;					// sound effect 6
	Phyre::PAudio::PAudioEvent	m_thud;					// sound effect 7
	Phyre::PAudio::PAudioEvent	m_ai;					// sound effect 8
	Phyre::PAudio::PAudioEvent	m_aidetected;			// sound effect 9
	Phyre::PAudio::PAudioEvent	m_music1;				// music 1
	Phyre::PAudio::PAudioEvent	m_music2;				// music 2
	Phyre::PAudio::PAudioEvent	m_music3;				// music 3

	float	m_volumeMultiplier;							// Music/Sound multiplier to apply to the music volume.
	float	m_Volume;									// Music/Sound volume.
	bool	m_clockPlaying;							    // Boolean to indicate if clock is playing.
	bool	m_clockStarted;							    // Boolean to indicate if clock has started.
	bool	m_movePlaying;							    // Boolean to indicate if character movement is playing.
	bool	m_moveStarted;							    // Boolean to indicate if character movement has started.
	bool	m_music1Playing;							// Boolean to indicate if music1 is playing.
	bool	m_music1Started;							// Boolean to indicate if music1 has started.
	bool	m_music2Playing;							// Boolean to indicate if music2 is playing.
	bool	m_music2Started;							// Boolean to indicate if music2 has started.
	bool	m_music3Playing;							// Boolean to indicate if music3 is playing.
	bool	m_music3Started;							// Boolean to indicate if music3 has started.
#endif //! PHYRE_ENABLE_AUDIO

	// Methods
	void pickNearestLights(const Vectormath::Aos::Vector3 &position);
	void configureViewports();
	void initInputMap();
	void spawnPickUps();
	static Phyre::PResult physicsDebugRender(Phyre::PWorldRendering::PWorldRendererFrame &frame, void *callbackData);

	Phyre::PResult gatherLocators(Phyre::PCluster &cluster, Phyre::PSharray<Phyre::PGameplay::PLocator *> &locators, const Phyre::PChar *name);
	Phyre::PResult attachLocatorsToNavMesh(Phyre::PCluster &cluster, const Phyre::PNavigation::PNavMesh &navMesh, Phyre::PSharray<Phyre::PGameplay::PLocator *> &locators, Phyre::PNavigation::PNavigationTargetComponent *targets);
	Phyre::PResult cloneMeshInstanceSimple(Phyre::PCluster &cluster, const Phyre::PRendering::PMeshInstance &sourceInstance, Phyre::PWorldMatrix &worldMatrix, Phyre::PInstanceList &preallocatedIL);

	// Texts
	TextHelper m_gameTextHelper;
	TextHelper m_endTextHelper;
	// Menu
	Phyre::PCameraOrthographic m_camera_menu;

	// Maximum number of events that can occur in a single frame.
	static const int							PC_MAX_EVENTS = 128;		

	// Gameplay Functions
	virtual void onPickupEnter(Phyre::PEntity *entity);
	virtual void pickupBoostSpeed(Phyre::PCharacter::PPhysicsCharacterControllerComponent *controller);
	virtual void pickupBoostJump(Phyre::PCharacter::PPhysicsCharacterControllerComponent *controller);
	virtual void resetBoost(Phyre::PCharacter::PPhysicsCharacterControllerComponent *controller);
	virtual Phyre::PResult DoPaintRaycast(Phyre::TeamID id);
	virtual void OnEndGameCalculateScores();
	virtual void firePaint(int i);

	// Pickup render bool
	bool speed = false;
	bool jump = false;

	// Raycast Angle Control
	std::vector<float> angles;

	// Menu
	PauseMenu *pauseMenu;

protected:
	// Phyre Framework overrides
	virtual Phyre::PResult prePhyreInit();
	virtual Phyre::PResult initApplication(Phyre::PChar **argv, Phyre::PInt32 argc);
	virtual Phyre::PResult handleInputs();
	virtual Phyre::PResult exitApplication();
	virtual Phyre::PResult initScene();
	virtual Phyre::PResult exitScene();
	virtual Phyre::PResult render();
	virtual Phyre::PResult resize();
	virtual Phyre::PResult animate();
	virtual Phyre::PResult setupGui();
public:
	SandboxApplication();
	static SandboxApplication &GetInstance();
	void reactivateScripts();
	Phyre::PCluster *getCluster();
	TextHelper*		getTextHelper();
};

#endif //!SANDBOXAPPLICATION_H

#endif // SHOULD_LOAD_SANDBOX_APPLICATION