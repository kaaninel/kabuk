# Main Application Layout Specification

## Core Layout Structure

### Navigation
- Bottom navigation bar on mobile/tablet
- Side rail navigation on desktop (collapsible)
- Four main views: Explore, Create, Chat, Apps
- Explore view is default landing page
- Navigation state persists across sessions

### View Container
- Takes full available space above navigation
- Maintains view state when switching
- Smooth transitions between views
- Support for nested navigation within views

## Navigation Components

### Bottom Navigation Bar
- Fixed position at bottom
- Material Design 3 navigation bar
- Icons with labels
- Active state indication
- Height: 64dp mobile, 80dp tablet

### Side Rail Navigation (Desktop)
- Rail width: 72px (collapsed), 256px (expanded)
- Expandable on hover/click
- Icons with labels on expand
- Pinnable in expanded state
- Matches system theme

## View Transitions

### Standard Transition
- Cross-fade between views (300ms)
- Maintain scroll position per view
- No transition when returning to suspended view

### View States
- Active: Currently visible
- Suspended: Hidden but maintained in memory
- Destroyed: Cleared from memory

## Responsive Behavior

### Breakpoints
- Mobile: 0-599px
- Tablet: 600-1239px
- Desktop: 1240px+

### Layout Changes
- Mobile: Bottom navigation
- Tablet: Bottom navigation
- Desktop: Side rail navigation
- Adaptive content padding

## Accessibility

### Navigation
- Keyboard shortcuts for view switching
- Screen reader support for navigation
- Focus indicators
- Skip navigation option

## Technical Notes

### View Management
- Views are lazy-loaded
- Memory management for suspended views
- State preservation between switches
- Deep linking support
