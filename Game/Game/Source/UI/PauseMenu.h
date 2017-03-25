#include <../Samples/Common/PhyreSamplesCommon.h>
#include <../Samples/Common/PhyreSamplesCommonScene.h>

class PauseMenu;
class SandboxApplication;

class PauseMenu
{
public:
	PauseMenu();
	~PauseMenu();
public:

	enum PMenuConstants
	{
		PE_MENU_TEXT_COUNT = 16,
		PE_MAX_DYNAMIC_TEXT_LENGTH = 64,
	};

	enum PMenuScreen
	{
		PE_MENU_SCREEN_DISABLED,

		// Screens
		PE_MENU_SCREEN_PAUSE,
		PE_MENU_SCREEN_STATUS,
		PE_MENU_SCREEN_GAMEOVER,
		PE_MENU_SCREEN_GAMOVER_IDLE,

		PE_MENU_SCREEN_GAMEOVER_OPEN,
		PE_MENU_SCREEN_GAMEOVER_CLOSE,

		// Animation States
		PE_MENU_SCREEN_LOADING_SCREEN_OPEN,
		PE_MENU_SCREEN_LOADING_SCREEN_CLOSE,
		PE_MENU_SCREEN_PAUSE_OPEN,
		PE_MENU_SCREEN_PAUSE_CLOSE,
		PE_MENU_SCREEN_EXIT_TO_PAUSE,
	};

	Phyre::PResult activate();

	Phyre::PResult initPauseMenu();
	Phyre::PResult initialize(SandboxApplication &app, Phyre::PCluster &textShaderCluster);//, TextHelper &helper);
	Phyre::PResult render(Phyre::PRendering::PRenderer &renderer, bool renderTransparentPass);
	Phyre::PResult handleInput(bool enterPressed, bool backPressed, bool hideMenu, bool upPressed, bool downPressed);
	Phyre::PResult animate(float timeDelta);
	Phyre::PResult onEndAnimation();


	bool isActive() const;
protected:
	Phyre::PResult setItemsInMenu(Phyre::PChar** title, Phyre::PInt32 numText, float x, float y, PMenuScreen menuScreen, bool containsHeader);
	Phyre::PResult processDownInput();
	Phyre::PResult processUpInput();
	Phyre::PResult processBackInput();
	Phyre::PResult processEnterInput();
	Phyre::PResult exitPauseMenu();
	Phyre::PResult changeSelection(uint32_t newSelection);
protected:

	SandboxApplication							*m_application;								// The application which owns the pause menu.

	Phyre::PText::PBitmapFont					*m_bitmapFont;								// The bitmap font object.
	Phyre::PText::PBitmapTextMaterial			*m_textMaterials[PE_MENU_TEXT_COUNT];		// The material used to render the text with.
	Phyre::PText::PBitmapFontText				*m_text[PE_MENU_TEXT_COUNT];

	Phyre::PRendering::PMeshInstance			*m_fullscreenMeshInstance;

	Phyre::PCluster								*m_textShaderCluster;
	Phyre::PCluster								*m_screenMeshCluster;


	Phyre::PUInt32								m_selectedOption;
	float										m_animationTime;
	PMenuScreen									m_currentMenuScreen;
	Phyre::PUInt32								m_numTextActive;
	Phyre::PUInt32								m_numTextTotal;
	float										m_primaryTextScale;
	static PauseMenu							*s_instance;
	TextHelper									p_Helper;
};