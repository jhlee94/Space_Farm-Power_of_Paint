#include <vector>
#include <../Samples/Common/PhyreSamplesCommon.h>
#include <../Samples/Common/PhyreSamplesCommonScene.h>

#define PLAYER_TEXT_BEGIN_INDEX 8
#define COLOUR_SPLAT_INDEX 1
#define TIMER_SYMBOL_INDEX 0
#define TIMER_INDEX 3

#define SCORE_BEGIN_INDEX 4 // needs to work with 4players
class TextHelper {
public:
	Phyre::PResult Initialise();
	Phyre::PResult CleanUp();
	Phyre::PResult AddText(Phyre::PChar * text, 
						   float positionX, 
						   float positionY, 
						   float size, 
						   float width,
						   float height,
						   Vectormath::Aos::Vector3 colour,
						   Phyre::PText::PBitmapFont* chosenFont,
						   Phyre::PCluster& cluster);
	
	Phyre::PResult AddText(Phyre::PChar * text, 
						   Phyre::PMatrix4 tMatrix, 
						   Vectormath::Aos::Vector3 colour, 
						   Phyre::PText::PBitmapFont* chosenFont, 
						   Phyre::PCluster & cluster);

	Phyre::PResult UpdateTextMatrix(int index, float width, float height);
	
	Phyre::PResult UpdateCharacterFollowText(int playerNo,
											 const Phyre::PCameraProjection *camera,
											 const Phyre::PCharacter::PPhysicsCharacterControllerComponent *controller,
											 const Phyre::PWorldMatrixOrbitController *camera_controller,
											 float viewportScale);

	Phyre::PSharray<Phyre::PText::PBitmapFontText *> getTexts() const;

	Vectormath::Aos::Vector3 GetPlayerColour(int playerNo);

	int GetPlayerScore(int playerNo);

	Phyre::PResult UpdateTime();

	Phyre::PChar * GetTimeMinutesAndSeconds();


	Phyre::PResult DrawAllText(int playerNo, Phyre::PRendering::PRenderer &m_renderer);

	// Simple getters for each of our fonts
	Phyre::PText::PBitmapFont* GetSplatFont() { return m_paintSplat; }
	Phyre::PText::PBitmapFont* GetMainUIFont() { return m_bitmapFont; }
	Phyre::PText::PBitmapFont* GetUIImagesFont() { return m_UI_ImagesFont; }

	void SetSplatFont(Phyre::PText::PBitmapFont& sp) { m_paintSplat = &sp; }
	void SetMainUIFont(Phyre::PText::PBitmapFont& mui) { m_bitmapFont = &mui; }
	void SetUIImagesFont(Phyre::PText::PBitmapFont& sui) { m_UI_ImagesFont = &sui; }

	Phyre::PRendering::PMaterial* getTextShader() const;
	void SetTextShader(Phyre::PRendering::PMaterial& mt) { m_textShader = &mt; }
protected:

	float m_time;
	int m_seconds;
	int m_minutes;

	// Texts
	Phyre::PText::PBitmapFont									*m_bitmapFont;							// The bitmap font object.
	Phyre::PText::PBitmapFont									*m_paintSplat;							// Font used for the player paint splat image ('I')
	Phyre::PText::PBitmapFont									*m_UI_ImagesFont;
	Phyre::PRendering::PMaterial								*m_textShader;							// Text shader to create texts
	Phyre::PRendering::PMaterial								*m_menuShader;
	Phyre::PSharray<Phyre::PText::PBitmapFontText *>			m_textList;								// List of texts
	Phyre::PSharray<Phyre::PText::PBitmapTextMaterial *>		m_textMaterials;						// List of text materials (Mapped to m_textList)

	// Colours associated with Players
	std::vector<Vectormath::Aos::Vector3> playerColours;
	std::vector<float>											m_fontScales;
	std::vector<Vectormath::Aos::Vector2>						m_positions;

public:
	std::vector<int>											m_scores;
};