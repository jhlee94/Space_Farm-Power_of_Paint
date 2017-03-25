#ifndef GAMECONFIG_H
#define GAMECONFIG_H

//Used to control if we will load up the game or the 
//programmers custom sandbox level. 
#define SHOULD_LOAD_SANDBOX_APPLICATION

//Disable this define to build without GameEdit
//#define PHYRE_SAMPLE_ENABLE_GAME_EDIT

//Disable this define to disable overview camera
//#define USE_OVERVIEW_CAMERA

// Description:
// The maximum length for the dynamic text string.
#define PD_MAX_DYNAMIC_TEXT_LENGTH	(32)

// Description:
// The number of bots in the level.
#define BOT_COUNT				(2)

// Description:
// The square root of the number of floating bots in the level.
#define FLOATER_SQUARE_ROOT		(2)

// Description:
// The number of floating bots in the level.
#define FLOATER_COUNT (FLOATER_SQUARE_ROOT * FLOATER_SQUARE_ROOT)

// Description:
// The number of player in the level.
#define MAX_NUMBER_OF_PLAYER (4)


#include <Phyre.h>
#include <Framework/PhyreFramework.h>
#include <Rendering/PhyreRendering.h>
#include <Physics/PhyrePhysics.h>
#include <Character/PhyreCharacter.h>
#include <Scripting/PhyreScripting.h>
#include <Gameplay/PhyreGameplay.h>
#include <Audio/PhyreAudio.h>
#include <Event/PhyreEvent.h>
#include <Navigation\PhyreNavigation.h>
#include <RecastNavigation/DetourCrowd/Include/DetourCrowd.h>
#include <Text/PhyreText.h>



#include "../AI/Bot.h"
#include "../AI/Floater.h"
#include "../AI/Target.h"
#include "../UI/TextHelper.h"
#include "../UI/PauseMenu.h"
#include "../ViewportConfig.h"

#ifdef SHOULD_LOAD_SANDBOX_APPLICATION
#include "../Application/SandboxApplication/SandboxApplication.h"
#else // ! SHOULD_LOAD_SANDBOX_APPLICATION
#include "../Application/GameApplication/GameApplication.h"
#endif


#endif