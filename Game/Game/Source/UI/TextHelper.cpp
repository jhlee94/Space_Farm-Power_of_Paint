#include "../GameConfig/GameConfig.h"

using namespace Phyre;
using namespace PRendering;
using namespace PText;
using namespace PSamplesCommon;

Phyre::PResult TextHelper::Initialise()
{
	// Search for the font objects in the loaded cluster
	m_bitmapFont = FindAssetRefObj<PBitmapFont>(NULL, "UIFont.fgen");
	if (!m_bitmapFont)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "Unable to find bitmap font object in cluster (Main UI font)");

	// Search for first wingdings font
	m_paintSplat = FindAssetRefObj<PBitmapFont>(NULL, "bubbles.fgen");
	if (!m_paintSplat)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "Unable to find bitmap font object in cluster (bubbles font)");

	// search for second wingdings font
	m_UI_ImagesFont = FindAssetRefObj<PBitmapFont>(NULL, "heyDings.fgen");
	if (!m_UI_ImagesFont)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "Unable to find bitmap font object in cluster (heyDingsFont)");

	m_textShader = FindAssetRefObj<PMaterial>(NULL, "PhyreText");
	if (!m_textShader)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "Unable to find text shader in cluster");

	m_menuShader = FindAssetRefObj<PMaterial>(NULL, "MenuScreen");
	if (!m_menuShader)
		return PHYRE_SET_LAST_ERROR(PE_RESULT_OBJECT_NOT_FOUND, "Unable to find text shader in cluster");

	// initialise time variables:
	m_time = 0.f;
	m_seconds = 0.f;
	m_minutes = 0.f;


	// set player colours for UI
	playerColours.push_back(Vectormath::Aos::Vector3(0.36f, 0.24f, 0.78f));
	playerColours.push_back(Vectormath::Aos::Vector3(1.0f, 0.5f, 0.f));
	playerColours.push_back(Vectormath::Aos::Vector3(0.0f, 0.5f, 0.8f));
	playerColours.push_back(Vectormath::Aos::Vector3(1.0f, 0.0f, 0.0f));


	//testList = PHYRE_ALLOCATE( Phyre::PText::PBitmapFontText, 7);
	// Add in some test scores
	m_scores.push_back(1234);
	m_scores.push_back(4568);
	m_scores.push_back(5678);
	m_scores.push_back(1111);

	return Phyre::PResult();
}

Phyre::PResult TextHelper::CleanUp()
{
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
}

Phyre::PResult TextHelper::AddText(
	Phyre::PChar * text,
	float positionX,
	float positionY,
	float size,
	float width,
	float height,
	Vectormath::Aos::Vector3 colour,
	Phyre::PText::PBitmapFont* chosenFont,
	Phyre::PCluster& cluster)
{
	// Create a new BitmapFontTextObject
	PBitmapFontText* fontText;

	// Create a material
	Phyre::PText::PBitmapTextMaterial* material;

	// Initialise it with our text material
	Phyre::PResult result = PText::PUtilityText::CreateText(*chosenFont, cluster,
		*m_textShader, fontText, material,
		PText::PUtilityText::PE_TEXT_RENDER_TECHNIQUE_ALPHA_BLEND);

	// Set the colour of the text:
	material->setColor(colour);

	PHYRE_TRY(fontText->setTextLength(PhyreCheckCast<PUInt32>(strlen(text))));

	// Set the text
	PHYRE_TRY(fontText->setText(text));

	// Position the text in the center on the screen, near the top
	// 30 = minimum font size
	float font_size = (size <= 10) ? 30 : 30 - size;
	if (!font_size)
		font_size = 1;
	float scale = 1.f / (font_size * material->getBitmapFontSize());
	//float width_scale = positionX / (width / 2.f);
	//float height_scale = positionY / (height / 2.f);
	float textHeight = fontText->getTextHeight() * scale;
	float textWidth = 0.5f * fontText->getTextWidth() * scale;
	float viewportScale = (float)width / (float)height;
	textHeight = (positionY < 0.f) ? 0.f : textHeight;
	m_fontScales.push_back(scale);
	m_positions.push_back(Vectormath::Aos::Vector2(positionX, positionY));

	PMatrix4 matrix = PMatrix4::identity();
	matrix.setUpper3x3(Vectormath::Aos::Matrix3::scale(Vectormath::Aos::Vector3(scale, scale, 1.0f)));
	matrix.setTranslation(Vectormath::Aos::Vector3((positionX * viewportScale) - textWidth, positionY - textHeight, 1.0f));
	fontText->setMatrix(matrix);

	// Finally, we add this to our vector of text
	m_textList.add(fontText);
	m_textMaterials.add(material);

	return PE_RESULT_NO_ERROR;
}

Phyre::PResult TextHelper::AddText(Phyre::PChar * text, Phyre::PMatrix4 tMatrix, Vectormath::Aos::Vector3 colour, Phyre::PText::PBitmapFont* chosenFont, Phyre::PCluster & cluster)
{
	// Create a new BitmapFontTextObject
	PBitmapFontText* fontText;

	// Create a material
	Phyre::PText::PBitmapTextMaterial* material;


	// Initialise it with our text material
	Phyre::PResult result = PText::PUtilityText::CreateText(*chosenFont, cluster,
		*m_textShader, fontText, material,
		PText::PUtilityText::PE_TEXT_RENDER_TECHNIQUE_ALPHA_BLEND);

	// Set the colour of the text:
	material->setColor(colour);

	PHYRE_TRY(fontText->setTextLength(PhyreCheckCast<PUInt32>(strlen(text))));

	// Set the text
	PHYRE_TRY(fontText->setText(text));

	fontText->setMatrix(tMatrix);

	// Finally, we add this to our vector of text
	m_textList.add(fontText);
	m_textMaterials.add(material);
	return PE_RESULT_NO_ERROR;
}

Phyre::PResult TextHelper::UpdateTextMatrix(int index, float width, float height) {
	auto* fontText = m_textList.getArray()[index];
	float scale = m_fontScales.at(index);

	float textHeight = fontText->getTextHeight() * scale;
	float textWidth = 0.5f * fontText->getTextWidth() * scale;
	float viewportScale = (float)width / (float)height;
	textHeight = (m_positions.at(index).getY() < 0.f) ? 0.f : textHeight;

	PMatrix4 matrix = PMatrix4::identity();
	matrix.setUpper3x3(Vectormath::Aos::Matrix3::scale(Vectormath::Aos::Vector3(scale, scale, 1.0f)));
	matrix.setTranslation(Vectormath::Aos::Vector3((m_positions.at(index).getX() * viewportScale) - (2 * textWidth), m_positions.at(index).getY() - textHeight, 1.0f));
	fontText->setMatrix(matrix);

	return PE_RESULT_NO_ERROR;
}

Phyre::PResult TextHelper::UpdateCharacterFollowText(
	int   playerNo,
	const Phyre::PCameraProjection *camera,
	const Phyre::PCharacter::PPhysicsCharacterControllerComponent *controller,
	const Phyre::PWorldMatrixOrbitController *camera_controller,
	float viewportScale)
{
	// Configure the position of Player Name Text
	PMatrix4 localToWorld = PMatrix4(controller->getEntity()->getWorldMatrix()->getMatrix());
	Vectormath::Aos::Vector4 position = camera->getViewProjectionMatrix() * Vectormath::Aos::Point3(localToWorld.getTranslation());
	position = position + Vectormath::Aos::Vector4(0.f, 4.f, 0.f, 0.f); // on top of character
	Vectormath::Aos::Vector3 screenPosition = position.getXYZ() / position.getW();
	screenPosition.setZ(1.0f);

	float scale = 1.0f / ((camera_controller->getDistance() / 4.f) * m_textMaterials.getArray()[PLAYER_TEXT_BEGIN_INDEX + playerNo]->getBitmapFontSize());
	float width = 0.5f * m_textList.getArray()[PLAYER_TEXT_BEGIN_INDEX + playerNo]->getTextWidth() * scale;

	m_textMaterials.getArray()[PLAYER_TEXT_BEGIN_INDEX + playerNo]->setColor(GetPlayerColour(playerNo));



	PMatrix4 matrix = PMatrix4::Identity();
	matrix.setUpper3x3(Vectormath::Aos::Matrix3::scale(Vectormath::Aos::Vector3(scale, scale, 1.0f)));
	matrix.setTranslation(Vectormath::Aos::Vector3((screenPosition.getX() * viewportScale) - width, screenPosition.getY(), 1.0f));
	m_textList.getArray()[PLAYER_TEXT_BEGIN_INDEX + playerNo]->setMatrix(matrix);

	return Phyre::PResult();
}


Vectormath::Aos::Vector3 TextHelper::GetPlayerColour(int playerNo)
{

	return playerColours.at(playerNo);
}

int TextHelper::GetPlayerScore(int playerNo)
{
	return m_scores.at(playerNo);

}


Phyre::PSharray<Phyre::PText::PBitmapFontText*> TextHelper::getTexts() const
{
	return m_textList;
}


PResult TextHelper::UpdateTime()
{
	m_time = PTimer::GetTime();

	m_minutes = (int)m_time / 60;
	m_seconds = (int)m_time % 60;

	return PE_RESULT_NO_ERROR;

}


Phyre::PChar* TextHelper::GetTimeMinutesAndSeconds()
{
	PChar timeString[PD_MAX_DYNAMIC_TEXT_LENGTH];

	PHYRE_SNPRINTF(timeString, PHYRE_STATIC_ARRAY_SIZE(timeString), "%i:%i", m_minutes, m_seconds);

	return timeString;

}

Phyre::PResult TextHelper::DrawAllText(int playerNo, Phyre::PRendering::PRenderer & m_renderer)
{
	//// We need to flush and sync the renderer to ensure that these render interface operations occur after the scene rendering has completed.
	//PHYRE_TRY(m_renderer.flushRender());
	//PHYRE_TRY(m_renderer.syncRender());

	if (playerNo >= 0) {

		// Render Text
		PHYRE_TRY(m_renderer.beginScene(0));

		// change colours accordingly
		if (m_textList.getArray()[COLOUR_SPLAT_INDEX]) {
			m_textMaterials[COLOUR_SPLAT_INDEX]->setColor(GetPlayerColour(playerNo));
		}

		// score variable test - it breaks? makes game stick on a black screen :(
		if (m_textList.getArray()[SCORE_BEGIN_INDEX + playerNo])
		{
			PChar scoreString[PD_MAX_DYNAMIC_TEXT_LENGTH];
			PHYRE_SNPRINTF(scoreString, PHYRE_STATIC_ARRAY_SIZE(scoreString), "%i", GetPlayerScore(playerNo));
			PHYRE_TRY(m_textList.getArray()[SCORE_BEGIN_INDEX + playerNo]->setText(scoreString));
		}

		//float tmp_time = PTimer::GetTime();
		//PHYRE_PRINTF("Hello! : %f\n", tmp_time);

		if (m_textList.getArray()[TIMER_INDEX])
		{

			PChar timerString[PD_MAX_DYNAMIC_TEXT_LENGTH];
			PHYRE_SNPRINTF(timerString, PHYRE_STATIC_ARRAY_SIZE(timerString), "%i:%i", m_minutes, m_seconds);
			PHYRE_TRY(m_textList.getArray()[TIMER_INDEX]->setText(timerString));
		}

		// Render the text objects
		for (PUInt32 i = 0; i < TIMER_INDEX; i++)
		{
			if (m_textList.getArray()[i]) {
				PHYRE_TRY(m_textList.getArray()[i]->renderText(m_renderer));
			}
		}


		if (m_textList.getArray()[TIMER_INDEX]) {
			const PChar* timerText = m_textList.getArray()[TIMER_INDEX]->getText();
			PHYRE_TRY(m_textList.getArray()[TIMER_INDEX]->renderText(m_renderer));
		}

		if (m_textList.getArray()[SCORE_BEGIN_INDEX + playerNo]) {
			PHYRE_TRY(m_textList.getArray()[SCORE_BEGIN_INDEX + playerNo]->renderText(m_renderer));
		}

		if (m_textList.getArray()[PLAYER_TEXT_BEGIN_INDEX + playerNo]) {

			PHYRE_TRY(m_textList.getArray()[PLAYER_TEXT_BEGIN_INDEX + playerNo]->renderText(m_renderer));
		}

	}

	//else if (playerNo == -1)
	//{
	//	PHYRE_TRY(m_textList.getArray()[TIMER_SYMBOL_INDEX]->renderText(m_renderer));
	//	PHYRE_TRY(m_textList.getArray()[TIMER_INDEX]->renderText(m_renderer));

	//}

	else {
		// Render Text
		//m_renderer.setSceneRenderPassType(PHYRE_GET_SCENE_RENDER_PASS_TYPE(DarkenBackground));
		PHYRE_TRY(m_renderer.beginScene(PRenderInterfaceBase::PE_CLEAR_COLOR_BUFFER_BIT | PRenderInterfaceBase::PE_CLEAR_DEPTH_BUFFER_BIT));
		// Render the text objects
		for (PUInt32 i = 0; i < m_textList.getCount(); i++)
		{
			if (m_textList.getArray()[i]) {
				PHYRE_TRY(m_textList.getArray()[i]->renderText(m_renderer));
			}
		}
	}

	PHYRE_TRY(m_renderer.endScene());

	return Phyre::PResult();
}

Phyre::PRendering::PMaterial * TextHelper::getTextShader() const
{
	return m_menuShader;
}
