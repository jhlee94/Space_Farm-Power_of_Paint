#include "../GameConfig/GameConfig.h"

using namespace Phyre;
using namespace PRendering;
using namespace PGeometry;
using namespace PText;
using namespace PAnimation;
using namespace Vectormath::Aos;

PHYRE_DEFINE_SCENE_RENDER_PASS_TYPE(DarkenBackground)

PauseMenu::PauseMenu() :
	m_currentMenuScreen(PE_MENU_SCREEN_DISABLED),
	m_selectedOption(0)
{
	p_Helper.Initialise();
	/*p_Helper.SetMainUIFont(*m_application->getTextHelper()->GetMainUIFont());
	p_Helper.SetSplatFont(*m_application->getTextHelper()->GetSplatFont());
	p_Helper.SetUIImagesFont(*m_application->getTextHelper()->GetUIImagesFont());
	p_Helper.SetTextShader(*m_application->getTextHelper()->getTextShader());*/
}

PauseMenu::~PauseMenu()
{
	p_Helper.CleanUp();
}

Phyre::PResult PauseMenu::initialize(SandboxApplication &app, PCluster &cluster)
{
	m_application = &app;
	m_fullscreenMeshInstance = PSamplesCommon::CreateFullscreenMeshInstance(cluster, *p_Helper.getTextShader());

	return PE_RESULT_NO_ERROR;
}

bool PauseMenu::isActive() const
{
	return m_currentMenuScreen != PE_MENU_SCREEN_DISABLED;
}

// Description:
// This function activates pause menu.
Phyre::PResult PauseMenu::activate()
{
	PHYRE_TRY(initPauseMenu());
	return PE_RESULT_NO_ERROR;
}


// Menus 
Phyre::PResult PauseMenu::initPauseMenu()
{
	static PChar *pauseMenuTextItems[] = { "Resume", "Exit" };

	float x = -0.65f;
	float y = 0.4f;

	setItemsInMenu(pauseMenuTextItems, sizeof(pauseMenuTextItems), x, y, PE_MENU_SCREEN_PAUSE_OPEN, false);

	return PE_RESULT_NO_ERROR;
}

Phyre::PResult PauseMenu::render(PRenderer &renderer, bool renderTransparentPass)
{
	PCameraOrthographic camera;
	camera.setOrthoAttributes(2.25f * 0.9f, 4.0f * 0.9f);
	camera.setNearPlane(-1000.0f);
	camera.setFarPlane(1000.0f);

	camera.setAspect((float)m_application->getWidth() / (float) m_application->getHeight());
	camera.updateViewMatrices();
	renderer.setCamera(camera);
	renderer.setViewport(0, 0, (float)m_application->getWidth(), (float)m_application->getHeight());
	PHYRE_TRY(renderer.setClearColor(0.0f, 0.0f, 0.0f, 0.2f));
	PHYRE_TRY(renderer.beginScene(PRenderInterfaceBase::PE_CLEAR_DEPTH_BUFFER_BIT));
	renderer.setSceneRenderPassType(PHYRE_GET_SCENE_RENDER_PASS_TYPE(DarkenBackground));
	renderer.renderMeshInstance(*m_fullscreenMeshInstance);
	PHYRE_TRY(renderer.endScene());

	// Render Text
	PHYRE_TRY(renderer.beginScene(0));
	renderer.setSceneRenderPassType(PHYRE_GET_SCENE_RENDER_PASS_TYPE(Transparent));
	// Render the text objects
	for (PUInt32 i = 0; i < p_Helper.getTexts().getCount(); i++)
	{
		if (p_Helper.getTexts().getArray()[i])
			PHYRE_TRY(p_Helper.getTexts().getArray()[i]->renderText(renderer));
	}
	PHYRE_TRY(renderer.endScene());

	return PE_RESULT_NO_ERROR;
}

PResult PauseMenu::animate(float timeDelta)
{
	m_animationTime -= timeDelta;
	if (m_animationTime < 0.0f)
		onEndAnimation();


	return PE_RESULT_NO_ERROR;
}


// Description:
// This function is triggered when animation is ended.
PResult PauseMenu::onEndAnimation()
{
	switch (m_currentMenuScreen)
	{
	case PE_MENU_SCREEN_PAUSE_OPEN:
		m_currentMenuScreen = PE_MENU_SCREEN_PAUSE;
		break;
	case PE_MENU_SCREEN_PAUSE_CLOSE:
		m_currentMenuScreen = PE_MENU_SCREEN_DISABLED;
		m_application->reactivateScripts();
		break;
	default:
		break;
	}

	return PE_RESULT_NO_ERROR;
}

Phyre::PResult PauseMenu::handleInput(bool enterPressed, bool backPressed, bool hideMenu, bool upPressed, bool downPressed)
{

	if (backPressed) processBackInput();
	if (upPressed) processUpInput();
	if (downPressed) processDownInput();
	if (enterPressed) processEnterInput();
	if (hideMenu) processBackInput();
	return PE_RESULT_NO_ERROR;
}

PResult PauseMenu::processEnterInput()
{
	switch (m_currentMenuScreen)
	{
	case PE_MENU_SCREEN_PAUSE:
	{
		switch (m_selectedOption)
		{
			//resume
		case 0:
			exitPauseMenu();
			break;
			//exit
		case 1:
			//go to main menu<when main menu is done>
			m_application->setQuit(true);
			break;
		default:
			break;
		}
	}
	}//switch
	return PE_RESULT_NO_ERROR;
}//processEnterInput


 // Description:
 // Process selection on the pause menu and sets the highlight colour 
 // Returns :
 // PE_RESULT_NO_ERROR: on Success 
PResult PauseMenu::changeSelection(uint32_t newSelection)
{
	Vector3 selectedColor(1.0f);
	Vector3 unselectedColor = selectedColor * 0.5f;

	for (PUInt32 i = 0; i < p_Helper.getTexts().getCount(); i++)
	{
		if (p_Helper.getTexts()[i])
			m_text[i] = p_Helper.getTexts()[i];
		if (i == newSelection)
			m_text[newSelection]->getTextMaterial().setColor(selectedColor);
		else
			m_text[i]->getTextMaterial().setColor(unselectedColor);
	}

	m_selectedOption = newSelection;

	return PE_RESULT_NO_ERROR;
}

// Description:
// This function process the UP Input press in Pause Menu  
Phyre::PResult PauseMenu::processUpInput()
{
	switch (m_currentMenuScreen)
	{
	case PE_MENU_SCREEN_PAUSE:
		if (m_selectedOption > 0)
			PHYRE_TRY(changeSelection(m_selectedOption - 1));
		break;
	}
}

//Description
//This function handles the DOWN input press in pause menu
Phyre::PResult PauseMenu::processDownInput()
{
	if (m_currentMenuScreen == PE_MENU_SCREEN_PAUSE)
		if (m_selectedOption < p_Helper.getTexts().getCount() - 1) PHYRE_TRY(changeSelection(m_selectedOption + 1));

	return PE_RESULT_NO_ERROR;
}
PResult PauseMenu::processBackInput()
{
	switch (m_currentMenuScreen)
	{
	case PE_MENU_SCREEN_PAUSE:
		PHYRE_TRY(exitPauseMenu());
		break;
	default:
		break;
	}
}

// Description:
// Function to exit Pause Menu .
// Returns :
// PE_RESULT_NO_ERROR: on Success  
PResult PauseMenu::exitPauseMenu()
{
	m_currentMenuScreen = PE_MENU_SCREEN_PAUSE_CLOSE;

	return PE_RESULT_NO_ERROR;
}

bool textLoaded;
Phyre::PResult PauseMenu::setItemsInMenu(Phyre::PChar** title, Phyre::PInt32 numText, float x, float y, PMenuScreen menuScreen, bool containsHeader)
{
	PMatrix4 matrix;
	PUInt32 startIndex = 0;
	if (containsHeader)
		startIndex = 1;

	for (PUInt32 i = startIndex; i < (numText / sizeof(PChar*)) + startIndex; ++i)
	{

		float actualY = y - (((float)i) * 0.15f);
		//setMenuText(title[i - startIndex], x, actualY, m_primaryTextScale, i);
		/*PChar* text = title[0];*/
		p_Helper.AddText(title[0], 0, 0, 22, m_application->getWidth(), m_application->getHeight(), Vectormath::Aos::Vector3(1.f), p_Helper.GetMainUIFont(), *m_application->getCluster());
		p_Helper.AddText(title[1], 0, -0.2f, 22, m_application->getWidth(), m_application->getHeight(), Vectormath::Aos::Vector3(1.f), p_Helper.GetMainUIFont(), *m_application->getCluster());
	}

	m_numTextTotal = numText / sizeof(PChar*) + startIndex;

	m_currentMenuScreen = menuScreen;

	PHYRE_TRY(changeSelection(startIndex));

	return PE_RESULT_NO_ERROR;
}