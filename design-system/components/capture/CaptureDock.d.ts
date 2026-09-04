export interface CaptureDockProps {
  onRecord?: ()=>void;
  onVideo?: ()=>void;
  onPhotos?: ()=>void;
  recording?: boolean;
  /** When live capture cannot work on this device, the sentence that takes the Record
   *  button's place. Null/undefined renders the Record button. */
  unavailable?: string | null;
  style?: React.CSSProperties;
}
export declare function CaptureDock(props: CaptureDockProps): JSX.Element;
