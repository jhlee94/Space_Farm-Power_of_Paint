#pragma once

// Description:
// The Bot class represents the class used by the bots to navigate the mesh.
class Bot
{
public:
	Phyre::PEntity										m_entity;				// The entity representing the bot.
	Phyre::PNavigation::PNavigationCrowdAgentComponent	*m_navigationComponent;	// The crowd component navigating the level.
																				// This is updated to navigate the bot through the level towards the target assigned to this component.
	Phyre::PNavigation::PNavigationTargetComponent		*m_navigationTarget;	// The target to allow floaters to follow the agent.
	Phyre::PWorldMatrix									*m_worldMatrix;			// The world matrix for this bot.

	Bot();
};
